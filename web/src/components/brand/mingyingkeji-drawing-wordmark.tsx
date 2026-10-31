import { cn } from '@/lib/utils';
import { LOGO_URL } from '@/lib/config';

interface MingyingkejiDrawingWordmarkProps {
  className?: string;
  loop?: boolean;
  title?: string;
}

export function MingyingkejiDrawingWordmark({
  className,
  loop: _loop = true,
  title = 'MINGYINGKEJI',
}: MingyingkejiDrawingWordmarkProps) {
  return (
    <img
      src={LOGO_URL}
      alt={title}
      role="img"
      className={cn('h-auto w-[150px] object-contain', className)}
    />
  );
}
