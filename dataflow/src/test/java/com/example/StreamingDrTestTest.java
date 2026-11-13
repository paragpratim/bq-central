package com.example;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import com.google.api.services.bigquery.model.ErrorProto;
import com.google.api.services.bigquery.model.TableDataInsertAllResponse.InsertErrors;
import com.google.api.services.bigquery.model.TableRow;
import java.util.Arrays;
import java.util.List;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.PipelineResult;
import org.apache.beam.sdk.PipelineRunner;
import org.apache.beam.sdk.io.GenerateSequence;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryInsertError;
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
    for (BigQueryIO.Write.Method method : methods()) {
      BigQueryIO.Write<TableRow> write =
          StreamingDrTest.bigQueryWrite("test-project:test_dataset.test_table", method);
      DisplayData displayData = DisplayData.from(write);
      assertEquals(method, write.getMethod());
      assertTrue(displayData.items().stream().anyMatch(
          item -> item.getKey().equals("createDisposition") && item.getValue().equals("CREATE_IF_NEEDED")));
      assertTrue(displayData.items().stream().anyMatch(
          item -> item.getKey().equals("writeDisposition") && item.getValue().equals("WRITE_APPEND")));
    }
  }

  @Test
  public void constructsUnboundedPipelineForEachMethod() {
    for (BigQueryIO.Write.Method method : methods()) {
      StreamingOptions options = PipelineOptionsFactory.as(StreamingOptions.class);
      options.setRunner(OfflineRunner.class);
      options.setStreaming(true);
      options.setTempLocation("gs://test-bucket/temp");
      Pipeline pipeline = Pipeline.create(options);
      WriteResult result = pipeline
          .apply(GenerateSequence.from(0).withRate(1, Duration.standardSeconds(1)))
          .apply(ParDo.of(new StreamingDrTest.GenerateRow()))
          .apply(StreamingDrTest.bigQueryWrite(
              "test-project:test_dataset.test_table", method).withoutValidation());
      StreamingDrTest.surfaceWriteErrors(result, method);
    }
  }

  @Test
  public void defaultsToStorageWriteAndRejectsUnsupportedMethods() {
    StreamingDrTest.Options options = PipelineOptionsFactory.as(StreamingDrTest.Options.class);
    assertEquals(BigQueryIO.Write.Method.STORAGE_WRITE_API, options.getWriteMethod());
    for (BigQueryIO.Write.Method method : methods()) {
      StreamingDrTest.Options parsed = PipelineOptionsFactory
          .fromArgs("--writeMethod=" + method.name()).as(StreamingDrTest.Options.class);
      assertEquals(method, parsed.getWriteMethod());
    }
    assertThrows(IllegalArgumentException.class,
        () -> StreamingDrTest.bigQueryWrite("test-project:test_dataset.test_table",
            BigQueryIO.Write.Method.DEFAULT));
    assertThrows(IllegalArgumentException.class,
        () -> StreamingDrTest.bigQueryWrite("test-project:test_dataset.test_table",
            BigQueryIO.Write.Method.STORAGE_API_AT_LEAST_ONCE));
  }

  private static List<BigQueryIO.Write.Method> methods() {
    return Arrays.asList(BigQueryIO.Write.Method.STORAGE_WRITE_API,
        BigQueryIO.Write.Method.STREAMING_INSERTS, BigQueryIO.Write.Method.FILE_LOADS);
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
    BigQueryInsertError error = new BigQueryInsertError(new TableRow(),
        new InsertErrors().setErrors(Arrays.asList(new ErrorProto().setMessage("streaming error"))), null);
    IllegalStateException failure = assertThrows(IllegalStateException.class,
        () -> new StreamingDrTest.ReportStreamingInsertFailure().process(error));
    assertTrue(failure.getMessage().contains("streaming error"));
  }
}
