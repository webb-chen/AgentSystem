'use client';

import type { PropsWithChildren } from 'react';
import { PublicRouteProviders } from '@/providers/public-route-providers';

/**
 * License 是公开页面（授权过期时也必须可访问），与 n/[token] 一样使用
 * PublicRouteProviders 包裹，提供 QueryClient / Theme / Toaster，
 * 但不依赖登录态。
 */
export default function LicenseLayout({ children }: PropsWithChildren) {
  return <PublicRouteProviders>{children}</PublicRouteProviders>;
}
