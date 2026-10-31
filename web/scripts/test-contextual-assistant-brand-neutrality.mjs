import { readFileSync } from 'node:fs';

const source = readFileSync('src/components/aichat/contextual/context-envelope.ts', 'utf8');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const forbiddenModelContext = [
  'MINGYINGKEJI AIChat system assistant',
  'AIChat is the MINGYINGKEJI sidebar operation assistant',
  'AIChat role: MINGYINGKEJI sidebar system assistant',
  'Describe AIChat as a MINGYINGKEJI operation assistant',
  'Current MINGYINGKEJI page context',
];

for (const phrase of forbiddenModelContext) {
  assert(!source.includes(phrase), `Context envelope must not expose branded identity: ${phrase}`);
}

assert(
  source.includes(
    "const PLATFORM_OPERATION_ASSISTANT_CONTEXT_ITEM_ID = 'assistant.platform_operation';"
  ),
  'The platform operation assistant must use a brand-neutral context resource ID.'
);
assert(
  source.includes("title: 'Platform operation assistant'"),
  'The model-visible context resource must use the neutral platform operation assistant title.'
);
assert(
  source.includes('item.id !== LEGACY_SYSTEM_CONTEXT_ITEM_ID'),
  'Legacy branded context resources must be removed when the current envelope is assembled.'
);

console.log('Contextual assistant brand neutrality checks passed.');
