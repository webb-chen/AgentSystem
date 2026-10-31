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
import { ShieldCheck, ShieldAlert, Upload, Loader2, RefreshCw } from 'lucide-react';

function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

export default function LicenseManagePage() {
  const { status, isLoading } = useLicenseStatus();
  const { data: machine } = useMachineCode();
  const uploadLicense = useUploadLicense();
  const reloadLicense = useReloadLicense();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);

  const license = status?.license ?? null;
  const isValid = status?.valid ?? false;
  const isPermanent = license?.permanent ?? false;
  const machineCode = machine?.machine_code ?? license?.machine_code ?? '';

  const handleUpload = () => {
    if (!selectedFile) return;
    uploadLicense.mutate(selectedFile, {
      onSettled: () => {
        setSelectedFile(null);
        if (fileInputRef.current) fileInputRef.current.value = '';
      },
    });
  };

  return (
    <div className="h-full overflow-y-auto bg-bg-canvas p-6">
      <div className="mx-auto max-w-2xl space-y-6">
        <div>
          <h1 className="text-xl font-semibold text-foreground">授权管理</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            查看当前授权状态、本机机器码，并上传统一授权平台签发的授权文件。
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">当前授权状态</CardTitle>
            <CardDescription>本部署实例的授权文件校验结果</CardDescription>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="space-y-3">
                <Skeleton className="h-6 w-full" />
                <Skeleton className="h-6 w-full" />
              </div>
            ) : (
              <div className="space-y-3">
                {isValid ? (
                  <Alert>
                    <ShieldCheck className="h-4 w-4 text-emerald-500" />
                    <AlertDescription>
                      <div className="flex flex-wrap items-center gap-2">
                        <Badge
                          variant="default"
                          className={status?.in_grace ? 'bg-amber-500' : 'bg-emerald-500'}
                        >
                          {status?.in_grace ? '宽限期' : '授权有效'}
                        </Badge>
                        <span className="text-sm text-muted-foreground">
                          {license?.product_display || license?.product}
                        </span>
                      </div>
                      <div className="mt-2 space-y-1 text-sm text-muted-foreground">
                        <div>客户：{license?.customer || '—'}</div>
                        <div>
                          到期：
                          {isPermanent ? '永久授权' : formatDateTime(license?.expire_time)}
                          {!isPermanent && typeof status?.remaining_days === 'number'
                            ? `（剩余 ${status.remaining_days} 天）`
                            : ''}
                        </div>
                      </div>
                    </AlertDescription>
                  </Alert>
                ) : (
                  <Alert variant="destructive">
                    <ShieldAlert className="h-4 w-4" />
                    <AlertDescription>
                      <div className="font-medium">
                        {licenseFailureMessage(status?.code ?? '', '授权无效')}
                      </div>
                      <div className="mt-1 text-xs opacity-70">
                        状态码：{status?.code ?? '—'}
                      </div>
                    </AlertDescription>
                  </Alert>
                )}

                <div className="rounded-md bg-muted p-3">
                  <div className="text-xs text-muted-foreground">本机机器码</div>
                  <code className="mt-1 block break-all font-mono text-xs">
                    {machineCode || '—'}
                  </code>
                  <p className="mt-1 text-xs text-muted-foreground">
                    机器绑定授权需要提供此机器码给平台管理员。
                  </p>
                </div>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => reloadLicense.mutate()}
                  disabled={reloadLicense.isPending}
                >
                  <RefreshCw className="h-4 w-4" /> 重新检测
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">上传授权文件</CardTitle>
            <CardDescription>
              仅接受统一授权平台签发的 .lic 文件；系统会先校验签名、产品、机器码与到期时间，
              通过后才会原子替换旧授权。
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <input
              ref={fileInputRef}
              type="file"
              accept=".lic,application/json"
              onChange={e => setSelectedFile(e.target.files?.[0] ?? null)}
              className="block w-full text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-primary file:px-4 file:py-2 file:text-sm file:font-medium file:text-primary-foreground hover:file:bg-primary/90"
            />
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
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
