'use client';

import { useRef, useState } from 'react';
import {
  licenseFailureMessage,
  useLicenseStatus,
  useMachineCode,
  useReloadLicense,
  useUploadLicense,
} from '@/hooks/use-license';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import { ShieldCheck, ShieldAlert, Upload, Loader2, ArrowRight, RefreshCw } from 'lucide-react';

function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

export default function LicensePage() {
  const { status, isLoading } = useLicenseStatus();
  const { data: machine } = useMachineCode();
  const uploadLicense = useUploadLicense();
  const reloadLicense = useReloadLicense();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);

  const isValid = status?.valid ?? false;
  const license = status?.license ?? null;
  const isPermanent = license?.permanent ?? false;
  const isGrace = status?.in_grace ?? false;
  const machineCode = machine?.machine_code ?? license?.machine_code ?? '';

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSelectedFile(e.target.files?.[0] ?? null);
  };

  const handleUpload = () => {
    if (!selectedFile) return;
    uploadLicense.mutate(selectedFile, {
      onSettled: () => {
        setSelectedFile(null);
        if (fileInputRef.current) fileInputRef.current.value = '';
      },
    });
  };

  const statusText = status
    ? licenseFailureMessage(status.code, status.message || '授权状态未知')
    : '';

  return (
    <div className="min-h-svh w-full flex items-center justify-center bg-background p-6">
      <Card className="w-full max-w-lg">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">授权管理</CardTitle>
          <CardDescription>
            上传统一授权平台签发的 license.lic 授权文件后即可正常使用平台
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-5">
          {isLoading ? (
            <div className="space-y-4">
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-10 w-full" />
            </div>
          ) : (
            <>
              {isValid ? (
                <Alert>
                  <ShieldCheck className="h-4 w-4 text-emerald-500" />
                  <AlertDescription>
                    <div className="flex items-center gap-2">
                      <Badge
                        variant="default"
                        className={isGrace ? 'bg-amber-500' : 'bg-emerald-500'}
                      >
                        {isGrace ? '宽限期' : '授权有效'}
                      </Badge>
                      {license?.product_display || license?.product ? (
                        <span className="text-sm text-muted-foreground">
                          {license?.product_display || license?.product}
                        </span>
                      ) : null}
                    </div>
                    <div className="mt-1 space-y-0.5 text-sm text-muted-foreground">
                      {license?.customer ? <div>客户：{license.customer}</div> : null}
                      <div>
                        {isPermanent
                          ? '永久授权，长期有效'
                          : `到期时间：${formatDateTime(license?.expire_time)}${
                              typeof status?.remaining_days === 'number' &&
                              status.remaining_days >= 0
                                ? `（剩余 ${status.remaining_days} 天）`
                                : ''
                            }`}
                      </div>
                      {isGrace ? <div className="text-amber-600">{statusText}</div> : null}
                    </div>
                  </AlertDescription>
                </Alert>
              ) : (
                <Alert variant="destructive">
                  <ShieldAlert className="h-4 w-4" />
                  <AlertDescription>
                    <div className="font-medium">尚未授权或授权已失效</div>
                    <div className="mt-1 text-sm">{statusText}</div>
                    {status?.code ? (
                      <div className="mt-1 text-xs opacity-70">状态码：{status.code}</div>
                    ) : null}
                  </AlertDescription>
                </Alert>
              )}

              <div className="space-y-3">
                <div className="text-sm font-medium">上传授权文件</div>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".lic,application/json"
                  onChange={handleFileChange}
                  className="block w-full text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-primary file:px-4 file:py-2 file:text-sm file:font-medium file:text-primary-foreground hover:file:bg-primary/90"
                />
                <p className="text-xs text-muted-foreground">
                  授权文件由统一授权平台签发；若为机器绑定授权，请先将下方机器码提供给管理员。
                </p>
                <Button
                  className="w-full"
                  onClick={handleUpload}
                  disabled={!selectedFile || uploadLicense.isPending}
                >
                  {uploadLicense.isPending ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" /> 上传中...
                    </>
                  ) : (
                    <>
                      <Upload className="h-4 w-4" /> 上传并激活授权
                    </>
                  )}
                </Button>
                <Button
                  variant="outline"
                  className="w-full"
                  onClick={() => reloadLicense.mutate()}
                  disabled={reloadLicense.isPending}
                >
                  <RefreshCw className="h-4 w-4" /> 重新检测授权
                </Button>
              </div>

              {machineCode ? (
                <div className="space-y-1">
                  <div className="text-sm font-medium">本机机器码</div>
                  <code className="block break-all rounded bg-muted px-2 py-1 font-mono text-xs">
                    {machineCode}
                  </code>
                </div>
              ) : null}

              {isValid ? (
                <Button
                  variant="outline"
                  className="w-full"
                  onClick={() => {
                    window.location.href = '/console';
                  }}
                >
                  进入平台 <ArrowRight className="h-4 w-4" />
                </Button>
              ) : null}
            </>
          )}
        </CardContent>
      </Card>
      {!isLoading && status?.code === 'license_not_init' ? (
        <div className="sr-only" role="status">
          {status.message}
        </div>
      ) : null}
    </div>
  );
}
