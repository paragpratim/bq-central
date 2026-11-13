package com.example;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import com.google.api.services.bigquery.model.TableRow;
import java.util.List;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.PipelineResult;
import org.apache.beam.sdk.PipelineRunner;
import org.apache.beam.sdk.io.GenerateSequence;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryStorageApiInsertError;
import org.apache.beam.sdk.io.gcp.bigquery.WriteResult;
import org.apache.beam.sdk.options.PipelineOptions;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.options.StreamingOptions;
import org.apache.beam.sdk.transforms.DoFnTester;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.display.DisplayData;
import org.joda.time.Duration;
import org.joda.time.Instant;
import org.junit.Test;

public class StreamingDrTestTest {
  public static class OfflineRunner extends PipelineRunner<PipelineResult> {
    public static OfflineRunner fromOptions(PipelineOptions options) {
      return new OfflineRunner();
    }

    @Override
    public PipelineResult run(Pipeline pipeline) {
      throw new UnsupportedOperationException("Offline graph construction only");
    }
  }

  @Test
  public void createsMissingTableAndAppendsToExistingTable() {
    BigQueryIO.Write<TableRow> write = StreamingDrTest.bigQueryWrite("test-project:test_dataset.test_table");
    DisplayData displayData = DisplayData.from(write);
    assertEquals(BigQueryIO.Write.Method.STORAGE_WRITE_API, write.getMethod());
    assertTrue(displayData.items().stream().anyMatch(
        item -> item.getKey().equals("createDisposition") && item.getValue().equals("CREATE_IF_NEEDED")));
    assertTrue(displayData.items().stream().anyMatch(
        item -> item.getKey().equals("writeDisposition") && item.getValue().equals("WRITE_APPEND")));
  }

  @Test
  public void constructsUnboundedStorageWritePipeline() {
    StreamingOptions options = PipelineOptionsFactory.as(StreamingOptions.class);
    options.setRunner(OfflineRunner.class);
    options.setStreaming(true);
    Pipeline pipeline = Pipeline.create(options);
    WriteResult result = pipeline
        .apply(GenerateSequence.from(0).withRate(1, Duration.standardSeconds(1)))
        .apply(ParDo.of(new StreamingDrTest.GenerateRow()))
        .apply(StreamingDrTest.bigQueryWrite("test-project:test_dataset.test_table").withoutValidation());
    result.getFailedStorageApiInserts().apply(ParDo.of(new StreamingDrTest.ReportFailure()));
  }

  @Test
  public void generatesAValidRow() throws Exception {
    try (DoFnTester<Long, TableRow> tester = DoFnTester.of(new StreamingDrTest.GenerateRow())) {
      List<TableRow> rows = tester.processBundle(0L);
      assertEquals(1, rows.size());
      Instant.parse((String) rows.get(0).get("generated_at"));
      int value = ((Number) rows.get(0).get("random_value")).intValue();
      assertTrue(value >= 0 && value < 1000);
    }
  }

  @Test
  public void insertFailuresAreSurfaced() {
    try {
      new StreamingDrTest.ReportFailure().process(new BigQueryStorageApiInsertError(new TableRow(), "test error"));
      throw new AssertionError("Expected failure");
    } catch (IllegalStateException expected) {
      assertTrue(expected.getMessage().contains("BigQuery Storage Write API failed: test error"));
    }
  }
}
