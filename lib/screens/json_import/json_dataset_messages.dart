import '../../core/constants/app_constants.dart';
import '../../core/constants/dataset_messages.dart';
import '../../domain/fulfilment/fulfilment_session.dart';
import '../../persistence/dataset_fingerprint.dart';

/// Ukrainian text for a dataset file the parser or fingerprint check refused.
String jsonDatasetRestoreMessage(DatasetRestoreRejected failure) {
  final message = failure.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  return switch (failure.reason) {
    DatasetRestoreReason.malformedUtf8 => AppStrings.jsonMalformedUtf8,
    DatasetRestoreReason.invalidFingerprint ||
    DatasetRestoreReason.fingerprintMismatch ||
    DatasetRestoreReason.malformedJson ||
    DatasetRestoreReason.invalidDataset => AppStrings.jsonImportRejected,
  };
}

/// Ukrainian text for a dataset [FulfilmentSession.open] refused.
String jsonDatasetProblemMessage(DatasetProblem problem) {
  return switch (problem.reason) {
    DatasetProblemReason.duplicateOrder => DatasetMessages.duplicateOrderId(
      problem.orderId ?? '',
    ),
    DatasetProblemReason.duplicateProduct => DatasetMessages.duplicateProductId(
      problem.orderId == null
          ? DatasetMessages.inDataset
          : DatasetMessages.orderId(problem.orderId!),
      problem.productId ?? '',
    ),
    DatasetProblemReason.duplicateStock => AppStrings.jsonDuplicateStock(
      productId: problem.productId,
      address: problem.address,
      serialNumber: problem.serialNumber,
    ),
  };
}
