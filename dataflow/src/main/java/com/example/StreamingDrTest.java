package com.example;

import com.google.api.services.bigquery.model.TableFieldSchema;
import com.google.api.services.bigquery.model.TableRow;
import com.google.api.services.bigquery.model.TableSchema;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.io.GenerateSequence;
import org.apache.beam.sdk.io.gcp.bigquery.*;
import org.apache.beam.sdk.options.Default;
import org.apache.beam.sdk.options.Description;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.options.Validation;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.ParDo;
import org.joda.time.Duration;
import org.joda.time.Instant;

import java.util.Arrays;
import java.util.concurrent.ThreadLocalRandom;

public final class StreamingDrTest {
    static TableSchema schema() {
        return new TableSchema().setFields(Arrays.asList(
                new TableFieldSchema().setName("generated_at").setType("TIMESTAMP").setMode("REQUIRED"),
                new TableFieldSchema().setName("random_value").setType("INTEGER").setMode("REQUIRED")));
    }

    static BigQueryIO.Write<TableRow> bigQueryWrite(
            String outputTable, String loadJobProjectId, BigQueryIO.Write.Method method) {
        if (method == BigQueryIO.Write.Method.FILE_LOADS
                && (loadJobProjectId == null || loadJobProjectId.isBlank())) {
            throw new IllegalArgumentException("--project is required for FILE_LOADS");
        }
        BigQueryIO.Write<TableRow> write = BigQueryIO.writeTableRows()
                .to(outputTable + tableSuffix(method))
                .withSchema(schema())
                .withCreateDisposition(BigQueryIO.Write.CreateDisposition.CREATE_IF_NEEDED)
                .withWriteDisposition(BigQueryIO.Write.WriteDisposition.WRITE_APPEND)
                .withMethod(method);
        return switch (method) {
            case STORAGE_WRITE_API -> write.withNumStorageWriteApiStreams(1)
                    .withTriggeringFrequency(Duration.standardSeconds(5));
            case STREAMING_INSERTS -> write.withExtendedErrorInfo()
                    .withFailedInsertRetryPolicy(InsertRetryPolicy.neverRetry());
            case FILE_LOADS -> write.withLoadJobProjectId(loadJobProjectId)
                    .withLoadJobReservation("projects/bq-central-56a6/locations/europe-west4/reservations/central-dr")
                    .withNumFileShards(1)
                    .withTriggeringFrequency(Duration.standardMinutes(1));
            default -> throw new IllegalArgumentException("Unsupported BigQuery write method: " + method);
        };
    }

    static String tableSuffix(BigQueryIO.Write.Method method) {
        return switch (method) {
            case STORAGE_WRITE_API -> "_storagewrite";
            case STREAMING_INSERTS -> "_streaming";
            case FILE_LOADS -> "_fileload";
            default -> throw new IllegalArgumentException("Unsupported BigQuery write method: " + method);
        };
    }

    static void surfaceWriteErrors(WriteResult result, BigQueryIO.Write.Method method) {
        switch (method) {
            case STORAGE_WRITE_API:
                result.getFailedStorageApiInserts().apply("Surface write errors", ParDo.of(new ReportFailure()));
                break;
            case STREAMING_INSERTS:
                result.getFailedInsertsWithErr()
                        .apply("Surface insert errors", ParDo.of(new ReportStreamingInsertFailure()));
                break;
            case FILE_LOADS:
                break;
            default:
                throw new IllegalArgumentException("Unsupported BigQuery write method: " + method);
        }
    }

    public static void main(String[] args) {
        Options options = PipelineOptionsFactory.fromArgs(args).withValidation().as(Options.class);
        options.setStreaming(true);
        BigQueryIO.Write.Method method = options.getWriteMethod();
        BigQueryIO.Write<TableRow> write = bigQueryWrite(options.getOutputTable(), options.getProject(), method);
        Pipeline pipeline = Pipeline.create(options);
        WriteResult result = pipeline
                .apply("Generate sequence", GenerateSequence.from(0).withRate(1, Duration.standardSeconds(1)))
                .apply("Generate random rows", ParDo.of(new GenerateRow()))
                .apply("Write to BigQuery", write);
        surfaceWriteErrors(result, method);
        pipeline.run();
    }

    public interface Options extends BigQueryOptions {
        @Description("Base destination table in project:dataset.table format; a write-method suffix is appended")
        @Validation.Required
        String getOutputTable();

        void setOutputTable(String value);

        @Description("BigQuery write method: STORAGE_WRITE_API, STREAMING_INSERTS, or FILE_LOADS")
        @Default.Enum("STORAGE_WRITE_API")
        BigQueryIO.Write.Method getWriteMethod();

        void setWriteMethod(BigQueryIO.Write.Method value);
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

    static class ReportStreamingInsertFailure extends DoFn<BigQueryInsertError, Void> {
        @ProcessElement
        public void process(@Element BigQueryInsertError error) {
            throw new IllegalStateException("BigQuery streaming insert failed: " + error.getError());
        }
    }
}
