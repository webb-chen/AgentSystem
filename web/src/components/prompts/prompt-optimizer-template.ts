export function extractPromptVariables(rawPrompt: string): string[] {
  const patterns = [
    /<mingyingkeji:(knowledge|skill|database|table|workflow)\b[^>]*>[\s\S]*?<\/mingyingkeji:\1>/g,
    /\{\{#[^{}]+#\}\}/g,
    /\{\{[^{}]+\}\}/g,
    /\$\{[^{}]+\}/g,
  ];
  const matches = new Set<string>();

  for (const pattern of patterns) {
    const found = rawPrompt.match(pattern);
    if (!found) continue;
    for (const item of found) {
      matches.add(item);
    }
  }

  return Array.from(matches);
}
