import { SentryReporter } from './reporters/sentry';
import type { CaptureOptions, Reporter } from './types';
import { MINGYINGKEJIReporter } from './mingyingkeji-reporter';

export type { CaptureOptions, Reporter, MINGYINGKEJIEvent } from './types';
export { NoopReporter, MINGYINGKEJIReporter } from './mingyingkeji-reporter';

export const mingyingkejiReporter = new MINGYINGKEJIReporter();

let initialized = false;

function readPublicReporterEnv(
  key: 'NEXT_PUBLIC_MINGYINGKEJI_REPORTERS' | 'NEXT_PUBLIC_SENTRY_DSN'
): string | undefined {
  if (typeof window !== 'undefined' && window.__ENV__) {
    const value = window.__ENV__[key];
    if (typeof value === 'string' && value.trim()) return value;
  }

  switch (key) {
    case 'NEXT_PUBLIC_MINGYINGKEJI_REPORTERS':
      return process.env.NEXT_PUBLIC_MINGYINGKEJI_REPORTERS;
    case 'NEXT_PUBLIC_SENTRY_DSN':
      return process.env.NEXT_PUBLIC_SENTRY_DSN;
  }
}

function selectedBuiltInReporters(): Set<string> {
  const configured = readPublicReporterEnv('NEXT_PUBLIC_MINGYINGKEJI_REPORTERS');
  if (configured) {
    const reporters = new Set(
      configured
        .split(/[\s,]+/)
        .map(item => item.trim().toLowerCase())
        .filter(Boolean)
    );
    if (reporters.has('none')) return new Set();
    return reporters;
  }

  return readPublicReporterEnv('NEXT_PUBLIC_SENTRY_DSN') ? new Set(['sentry']) : new Set();
}

export function initializeMINGYINGKEJIReporter(): void {
  if (initialized || typeof window === 'undefined') return;
  initialized = true;

  const selected = selectedBuiltInReporters();
  if (selected.has('sentry') && readPublicReporterEnv('NEXT_PUBLIC_SENTRY_DSN')) {
    const sentryReporter = new SentryReporter();
    mingyingkejiReporter.register(sentryReporter);
    sentryReporter.initialize();
  }
}

/** Registers a customer adapter. Duplicate adapter names are ignored. */
export function registerReporter(reporter: Reporter): void {
  mingyingkejiReporter.register(reporter);
}

export function captureError(
  error: unknown,
  name = 'mingyingkeji.error',
  options: CaptureOptions = {}
): void {
  initializeMINGYINGKEJIReporter();
  mingyingkejiReporter.report({
    name,
    kind: 'error',
    level: options.level || 'error',
    error,
    tags: options.tags,
    attributes: options.attributes,
    occurredAt: new Date().toISOString(),
  });
}

export function captureEvent(name: string, options: CaptureOptions = {}): void {
  initializeMINGYINGKEJIReporter();
  mingyingkejiReporter.report({
    name,
    kind: 'event',
    level: options.level || 'info',
    tags: options.tags,
    attributes: options.attributes,
    occurredAt: new Date().toISOString(),
  });
}

export function captureRouterTransitionStart(...args: unknown[]): void {
  initializeMINGYINGKEJIReporter();
  mingyingkejiReporter.onRouterTransitionStart(...args);
}
