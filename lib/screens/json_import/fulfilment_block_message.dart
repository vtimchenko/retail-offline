import '../../application/fulfilment_application.dart';
import '../../application/fulfilment_ui_controller.dart';
import '../../core/constants/app_constants.dart';

/// Ukrainian explanation of a persistence [block].
String fulfilmentBlockText(PersistenceBlock block) {
  return switch (block) {
    PersistenceBlock.revisionConflict => AppStrings.jsonRevisionConflict,
    PersistenceBlock.storageUnavailable => AppStrings.jsonStorageUnavailable,
    PersistenceBlock.storageFailed => AppStrings.jsonStorageFailed,
    PersistenceBlock.corrupted => AppStrings.jsonCorrupted,
    PersistenceBlock.unsupportedVersion => AppStrings.jsonUnsupportedVersion,
    PersistenceBlock.revisionOverflow => AppStrings.jsonRevisionOverflow,
  };
}

/// Message for a blocked fulfilment screen.
///
/// Uses [FulfilmentUiController.block] when storage reported one. An
/// unexpected failure without a block uses the generic read message.
String fulfilmentBlockedMessage(FulfilmentUiController controller) {
  final block = controller.block;
  if (block != null) return fulfilmentBlockText(block);
  return AppStrings.jsonReadFailed;
}
