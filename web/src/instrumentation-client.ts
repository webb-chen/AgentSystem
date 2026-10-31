import { captureRouterTransitionStart, initializeMINGYINGKEJIReporter } from '@/lib/observability';

initializeMINGYINGKEJIReporter();

export const onRouterTransitionStart = captureRouterTransitionStart;
