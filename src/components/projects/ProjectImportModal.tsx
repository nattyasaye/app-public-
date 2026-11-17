import React, { useEffect, useRef, useState } from 'react';
import { Sparkles, Upload, X } from 'lucide-react';
import {
  BIM_OUTREACH_CAMPAIGN_TITLE,
  PreparedProjectPackageImport,
  ProjectPackageError,
  projectsService,
  serializeBimOutreachTemplateJson,
} from '../../services/projectsService';
import {
  DaywellButton,
  DaywellCard,
  DaywellIconButton,
  DaywellStatusBanner,
} from '../ui';

export interface ProjectImportModalProps {
  isOpen: boolean;
  onClose: () => void;
  onImported: (result: PreparedProjectPackageImport) => void;
}

export function ProjectImportModal({
  isOpen,
  onClose,
  onImported,
}: ProjectImportModalProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [rawJson, setRawJson] = useState('');
  const [selectedFilename, setSelectedFilename] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    setRawJson('');
    setSelectedFilename(null);
    setErrorMsg(null);
  }, [isOpen]);

  if (!isOpen) return null;

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    try {
      const content = await file.text();
      setSelectedFilename(file.name);
      setRawJson(content);
      setErrorMsg(null);
    } catch (err) {
      setErrorMsg(
        err instanceof Error
          ? err.message
          : 'Unable to read selected project file.'
      );
    }
  };

  const handleImportJson = (jsonPayload: string) => {
    setErrorMsg(null);
    try {
      const result = projectsService.importProjectPackage(jsonPayload);
      onImported(result);
    } catch (err) {
      if (err instanceof ProjectPackageError || err instanceof Error) {
        setErrorMsg(err.message);
      } else {
        setErrorMsg('Unable to import project package.');
      }
    }
  };

  const handleImportSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    handleImportJson(rawJson);
  };

  const handleLoadBimTemplate = () => {
    handleImportJson(serializeBimOutreachTemplateJson());
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Import Project Package"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="w-full max-w-lg bg-[var(--dw-elevated)] rounded-[var(--dw-radius-xl)] p-5 shadow-2xl border border-[var(--dw-border)] space-y-4 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="dw-type-title text-[var(--dw-text-primary)]">
              Import Project (.daywellproject)
            </h2>
            <p className="text-[11px] text-[var(--dw-text-muted)]">
              Adds the package or template as a new project without overwriting existing projects.
            </p>
          </div>
          <DaywellIconButton
            label="Close import dialog"
            size="compact"
            tone="muted"
            onClick={onClose}
            icon={<X className="w-4 h-4" />}
          />
        </div>

        {errorMsg ? (
          <DaywellStatusBanner tone="error" message={errorMsg} liveRegion />
        ) : null}

        <DaywellCard variant="subtle" padding="compact" radius="md" className="space-y-2">
          <div className="space-y-0.5">
            <div className="dw-type-caption uppercase tracking-wider text-[var(--dw-text-muted)]">
              Load Template
            </div>
            <p className="text-xs font-bold text-[var(--dw-text-primary)]">
              {BIM_OUTREACH_CAMPAIGN_TITLE}
            </p>
            <p className="text-[11px] text-[var(--dw-text-secondary)]">
              1,000 target emails across 100 US cities grouped by Census region · 22 days (46/day · Hidar 9–30, 2019 E.C.)
            </p>
          </div>
          <DaywellButton
            label="Load BIM Outreach Template"
            variant="tonal"
            size="compact"
            fullWidth
            leadingIcon={<Sparkles className="w-4 h-4" />}
            onClick={handleLoadBimTemplate}
          />
        </DaywellCard>

        <form onSubmit={handleImportSubmit} className="space-y-4">
          <div className="space-y-2">
            <input
              ref={fileInputRef}
              type="file"
              accept=".daywellproject,.json,application/json"
              onChange={handleFileChange}
              className="hidden"
              aria-label="Choose .daywellproject file"
            />
            <DaywellButton
              label="Choose .daywellproject File"
              variant="outlined"
              fullWidth
              leadingIcon={<Upload className="w-4 h-4" />}
              onClick={() => fileInputRef.current?.click()}
            />
            {selectedFilename && (
              <p className="text-[11px] text-[var(--dw-text-secondary)] truncate">
                Loaded file: <span className="font-semibold">{selectedFilename}</span>
              </p>
            )}
          </div>

          <div className="space-y-1.5">
            <label className="block dw-type-label text-[var(--dw-text-secondary)]">
              Or Paste Package JSON
            </label>
            <textarea
              rows={6}
              value={rawJson}
              onChange={(e) => {
                setRawJson(e.target.value);
                if (errorMsg) setErrorMsg(null);
              }}
              placeholder='{"formatId": "daywell_project_package", "formatVersion": 1, ...}'
              className="w-full rounded-[var(--dw-radius-md)] bg-[var(--dw-card)] text-[var(--dw-text-primary)] placeholder:text-[var(--dw-text-muted)] border border-[var(--dw-border)] px-3 py-2 text-xs font-mono focus:outline-none focus:border-[var(--dw-primary)] focus:ring-2 focus:ring-[var(--dw-primary)]/25"
            />
          </div>

          <div className="flex items-center justify-end gap-2 pt-2 border-t border-[var(--dw-divider)]">
            <DaywellButton
              label="Cancel"
              variant="outlined"
              onClick={onClose}
            />
            <DaywellButton
              type="submit"
              label="Import Project"
              variant="primary"
              disabled={!rawJson.trim()}
            />
          </div>
        </form>
      </div>
    </div>
  );
}
