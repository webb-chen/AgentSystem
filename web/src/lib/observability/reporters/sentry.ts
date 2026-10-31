import {
  captureException,
  captureMessage,
  captureRouterTransitionStart,
  initializeSentryClient,
} from '@/lib/sentry/client';
import type { Reporter, MINGYINGKEJIEvent, MINGYINGKEJIEventLevel } from '../types';

/** Sentry adapter; all Sentry SDK types remain behind this boundary. */
export class SentryReporter implements Reporter {
  readonly name = 'sentry';

  initialize(): void {
    initializeSentryClient();
  }

  report(event: Readonly<MINGYINGKEJIEvent>): void {
    const configureScope = (scope: {
      setContext(name: string, context: Record<string, unknown>): void;
      setTag(key: string, value: string | number | boolean): void;
      setLevel(level: MINGYINGKEJIEventLevel): void;
    }) => {
      scope.setLevel(event.level);
      scope.setTag('mingyingkeji.event', event.name);
      scope.setTag('mingyingkeji.kind', event.kind);
      for (const [key, value] of Object.entries(event.tags || {})) {
        scope.setTag(key, value);
      }
      for (const [key, value] of Object.entries(event.attributes || {})) {
        const context =
          value && typeof value === 'object' && !Array.isArray(value)
            ? (value as Record<string, unknown>)
            : { value };
        scope.setContext(key, context);
      }
    };

    if (event.error !== undefined) {
      captureException(event.error, configureScope);
      return;
    }
    captureMessage(event.name, configureScope);
  }

  onRouterTransitionStart(...args: unknown[]): void {
    captureRouterTransitionStart(...args);
  }
}
