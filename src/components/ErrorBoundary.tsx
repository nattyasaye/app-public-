import React, { Component, ErrorInfo, ReactNode } from 'react';
import { AlertTriangle, RefreshCw, Trash2 } from 'lucide-react';
import { DaywellButton, DaywellCard } from './ui';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): State {
    return {
      hasError: true,
      error,
      errorInfo: null,
    };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Daywell Uncaught UI Exception:', error, errorInfo);
    this.setState({ errorInfo });
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.reload();
  };

  handleSafeRecovery = () => {
    // Retain user data if possible, but reset current navigation route to 'today'
    try {
      sessionStorage.clear();
    } catch {
      // ignore
    }
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.href = window.location.pathname;
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-[var(--dw-canvas)] text-[var(--dw-text-primary)] flex flex-col items-center justify-center p-6">
          <DaywellCard
            radius="xl"
            padding="lg"
            className="w-full max-w-md shadow-xl text-center space-y-5 sm:p-8"
          >
            <div
              className="w-14 h-14 bg-[var(--dw-error-container)] text-[var(--dw-on-error-container)] rounded-[var(--dw-radius-lg)] flex items-center justify-center mx-auto"
              aria-hidden="true"
            >
              <AlertTriangle className="w-7 h-7" />
            </div>

            <div className="space-y-1.5">
              <h2 className="dw-type-heading text-[var(--dw-text-primary)]">
                Application Encountered an Error
              </h2>
              <p className="dw-type-body-compact text-[var(--dw-text-secondary)]">
                Daywell caught an unexpected error. Your offline data is preserved safely.
              </p>
            </div>

            {this.state.error && (
              <div className="text-left bg-[var(--dw-surface-subtle)] border border-[var(--dw-border)] rounded-[var(--dw-radius-md)] p-3 max-h-36 overflow-y-auto dw-type-mono text-[var(--dw-error)] break-words">
                {this.state.error.message || 'Unknown runtime error'}
              </div>
            )}

            <div className="flex flex-col sm:flex-row gap-3 pt-2">
              <DaywellButton
                label="Reload Application"
                variant="primary"
                onClick={this.handleRetry}
                leadingIcon={<RefreshCw className="w-4 h-4" />}
                className="flex-1"
              />
              <DaywellButton
                label="Recover Home"
                variant="outlined"
                onClick={this.handleSafeRecovery}
                leadingIcon={<Trash2 className="w-4 h-4" />}
              />
            </div>
          </DaywellCard>
        </div>
      );
    }

    return this.props.children;
  }
}
