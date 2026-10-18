import '../../core/errors/dataset_parse_exception.dart';
import '../../models/retail_dataset.dart';
import 'dataset_validator.dart';
import 'precision_json_decoder.dart';

/// Parses a retail JSON dataset and validates it.
///
/// The result is only a value. This parser does not store it.
class JsonDatasetParser {
  const JsonDatasetParser();

  /// Decodes [source] and returns the dataset.
  ///
  /// Throws [JsonSyntaxException] when [source] is not JSON, and
  /// [DatasetValidationException] when a required field is invalid. The
  /// first invalid required field rejects the whole dataset.
  RetailDataset parse(String source) {
    final value = const PrecisionJsonDecoder().decode(source);
    return const DatasetValidator().validate(value);
  }
}
