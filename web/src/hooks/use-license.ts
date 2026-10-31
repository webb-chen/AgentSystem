'use client';

// License hooks powered by React Query (ULP v1 format).
// English comments only. Strict TypeScript (no any).

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { getErrorMessage } from '@/utils/error-notifications';
import { licenseService } from '@/services/license.service';
import type { LicenseStatusResponse, MachineCodeResponse } from '@/services/types/license';

const LICENSE_QUERY_KEY = 'license' as const;
const getLicenseStatusKey = () => [LICENSE_QUERY_KEY, 'status'] as const;
const getMachineCodeKey = () => [LICENSE_QUERY_KEY, 'machine-code'] as const;

const LICENSE_FAILURE_MESSAGES: Record<string, string> = {
  license_not_init: '授权模块未初始化，请检查服务配置',
  license_no_public_key: '内置公钥未配置，请使用厂商重新构建的程序',
  license_missing: '未找到授权文件，请上传授权文件',
  license_malformed: '授权文件结构或编码损坏，请重新上传',
  license_bad_signature: '授权签名校验失败，文件可能被篡改或非本平台签发',
  license_expired: '授权已到期，请续期后重新上传',
  license_clock_rollback: '检测到系统时间回拨，请校准系统时间后重试',
  license_machine_mismatch: '授权绑定了其他机器，请申请本机授权',
  license_product_mismatch: '授权文件属于其他产品，请上传本产品的授权',
};

export function licenseFailureMessage(code: string, fallback: string): string {
  return LICENSE_FAILURE_MESSAGES[code] ?? fallback;
}

export interface UseLicenseStatusReturn {
  status: LicenseStatusResponse | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<unknown>;
}

export function useLicenseStatus(): UseLicenseStatusReturn {
  const { data, isLoading, error, refetch } = useQuery<LicenseStatusResponse, unknown>({
    queryKey: getLicenseStatusKey(),
    queryFn: () => licenseService.getStatus(),
    staleTime: 30 * 1000,
    gcTime: 5 * 60 * 1000,
    refetchOnWindowFocus: false,
    retry: false,
  });

  return {
    status: data ?? null,
    isLoading,
    error: error ? ((error as { message?: string }).message ?? 'error') : null,
    refetch,
  };
}

export function useUploadLicense() {
  const queryClient = useQueryClient();

  return useMutation<LicenseStatusResponse, unknown, File>({
    mutationFn: (file: File) => licenseService.upload(file),
    onSuccess: result => {
      if (!result.valid) {
        toast.error(licenseFailureMessage(result.code, result.message || '授权文件上传失败'));
        return;
      }
      toast.success('授权文件上传成功');
      queryClient.invalidateQueries({ queryKey: getLicenseStatusKey() });
    },
    onError: (err: unknown) => {
      toast.error(getErrorMessage(err) || '授权文件上传失败');
    },
  });
}

export function useReloadLicense() {
  const queryClient = useQueryClient();

  return useMutation<LicenseStatusResponse, unknown, void>({
    mutationFn: () => licenseService.reload(),
    onSuccess: result => {
      if (!result.valid) {
        toast.error(licenseFailureMessage(result.code, result.message || '授权无效'));
        return;
      }
      toast.success('授权已重新检测');
      queryClient.invalidateQueries({ queryKey: getLicenseStatusKey() });
    },
    onError: (err: unknown) => {
      toast.error(getErrorMessage(err) || '重新检测失败');
    },
  });
}

export function useMachineCode() {
  return useQuery<MachineCodeResponse, unknown>({
    queryKey: getMachineCodeKey(),
    queryFn: () => licenseService.getMachineCode(),
    staleTime: 5 * 60 * 1000,
    refetchOnWindowFocus: false,
    retry: false,
  });
}
