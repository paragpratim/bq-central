package com.example;

import com.google.api.services.bigquery.model.TableFieldSchema;
import com.google.api.services.bigquery.model.TableRow;
import com.google.api.services.bigquery.model.TableSchema;
import java.util.Arrays;
import java.util.concurrent.ThreadLocalRandom;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.io.GenerateSequence;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryStorageApiInsertError;
import org.apache.beam.sdk.io.gcp.bigquery.WriteResult;
import org.apache.beam.sdk.options.Description;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.options.StreamingOptions;
import org.apache.beam.sdk.options.Validation;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.ParDo;
import org.joda.time.Duration;
import org.joda.time.Instant;

public final class StreamingDrTest {
  public interface Options extends StreamingOptions {
    @Description("Destination table in project:dataset.table format")
    @Validation.Required
    String getOutputTable();
    void setOutputTable(String value);
  }

  static TableSchema schema() {
    return new TableSchema().setFields(Arrays.asList(
        new TableFieldSchema().setName("generated_at").setType("TIMESTAMP").setMode("REQUIRED"),
        new TableFieldSchema().setName("random_value").setType("INTEGER").setMode("REQUIRED")));
  }

  static class GenerateRow extends DoFn<Long, TableRow> {
    @ProcessElement
    public void process(OutputReceiver<TableRow> output) {
      output.output(new TableRow()
          .set("generated_at", Instant.now().toString())
          .set("random_value", ThreadLocalRandom.current().nextInt(1000)));
    }
  }

  static class ReportFailure extends DoFn<BigQueryStorageApiInsertError, Void> {
    @ProcessElement
    public void process(@Element BigQueryStorageApiInsertError error) {
      throw new IllegalStateException("BigQuery Storage Write API failed: " + error.getErrorMessage());
    }
  }

  static BigQueryIO.Write<TableRow> bigQueryWrite(String outputTable) {
    return BigQueryIO.writeTableRows()
        .to(outputTable)
        .withSchema(schema())
        .withCreateDisposition(BigQueryIO.Write.CreateDisposition.CREATE_IF_NEEDED)
        .withWriteDisposition(BigQueryIO.Write.WriteDisposition.WRITE_APPEND)
        .withMethod(BigQueryIO.Write.Method.STORAGE_WRITE_API)
        .withNumStorageWriteApiStreams(1)
        .withTriggeringFrequency(Duration.standardSeconds(5));
  }

  public static void main(String[] args) {
    Options options = PipelineOptionsFactory.fromArgs(args).withValidation().as(Options.class);
    options.setStreaming(true);
    Pipeline pipeline = Pipeline.create(options);
    WriteResult result = pipeline
        .apply("Generate sequence", GenerateSequence.from(0).withRate(1, Duration.standardSeconds(1)))
        .apply("Generate random rows", ParDo.of(new GenerateRow()))
        .apply("Write with Storage Write API", bigQueryWrite(options.getOutputTable()));
    result.getFailedStorageApiInserts().apply("Surface write errors", ParDo.of(new ReportFailure()));
    pipeline.run();
  }
}
