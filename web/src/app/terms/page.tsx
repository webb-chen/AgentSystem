import type { Metadata } from 'next';
import LegalMarkdownPage from '../_legal/legal-markdown-page';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'MINGYINGKEJI服务条款',
};

export default function TermsPage() {
  return <LegalMarkdownPage document="terms" />;
}
