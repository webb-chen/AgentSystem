export type MINGYINGKEJIEventKind = 'error' | 'event';
export type MINGYINGKEJIEventLevel = 'debug' | 'info' | 'warning' | 'error' | 'fatal';

export interface MINGYINGKEJIEvent {
  name: string;
  kind: MINGYINGKEJIEventKind;
  level: MINGYINGKEJIEventLevel;
  error?: unknown;
  tags?: Record<string, string | number | boolean>;
  attributes?: Record<string, unknown>;
  occurredAt: string;
}

export interface CaptureOptions {
  level?: MINGYINGKEJIEventLevel;
  tags?: Record<string, string | number | boolean>;
  attributes?: Record<string, unknown>;
}

/** Provider-neutral extension point for Sentry, OpenTelemetry, or customer adapters. */
export interface Reporter {
  readonly name: string;
  report(event: Readonly<MINGYINGKEJIEvent>): void | Promise<void>;
  flush?(): void | Promise<void>;
  onRouterTransitionStart?(...args: unknown[]): void;
}
