import { cn } from '@/lib/utils';
import { LOGO_URL } from '@/lib/config';

interface MingyingkejiWordmarkProps {
  className?: string;
  title?: string;
}

export function MingyingkejiWordmark({
  className,
  title = 'MINGYINGKEJI',
}: MingyingkejiWordmarkProps) {
  return (
    <img
      src={LOGO_URL}
      alt={title}
      role="img"
      className={cn('h-auto w-[116px] object-contain', className)}
    />
  );
}
