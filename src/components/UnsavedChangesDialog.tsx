import React from 'react';
import { DaywellConfirmationDialog } from './ui';

interface UnsavedChangesDialogProps {
  isOpen: boolean;
  onContinueEditing?: () => void;
  onDiscardChanges?: () => void;
  onStay?: () => void;
  onDiscard?: () => void;
  title?: string;
  message?: string;
  description?: string;
}

export function UnsavedChangesDialog({
  isOpen,
  onContinueEditing,
  onDiscardChanges,
  onStay,
  onDiscard,
  title = 'Discard unsaved changes?',
  message,
  description,
}: UnsavedChangesDialogProps) {
  const handleContinue = onStay || onContinueEditing || (() => {});
  const handleDiscard = onDiscard || onDiscardChanges || (() => {});
  const displayMessage =
    description ||
    message ||
    'You have unsaved changes that will be lost if you leave now. Would you like to continue editing or discard your changes?';

  return (
    <DaywellConfirmationDialog
      isOpen={isOpen}
      title={title}
      description={displayMessage}
      cancelLabel="Continue Editing"
      confirmLabel="Discard Changes"
      destructive
      onCancel={handleContinue}
      onConfirm={handleDiscard}
    />
  );
}
