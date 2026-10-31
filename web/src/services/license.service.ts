import { BaseService } from '@/lib/http/services';
import type { LicenseStatusResponse, MachineCodeResponse } from './types/license';

/**
 * LicenseService
 * Handles Unified License Platform (ULP) endpoints under `/console/api/license`.
 * All requests skip auth so they work even when the license is expired
 * (the license routes are recovery paths in the backend middleware).
 */
class LicenseService extends BaseService {
  constructor() {
    super({ endpoint: 'main', basePath: '/console/api/license' });
  }

  /**
   * Get current license status.
   * GET /console/api/license/status
   */
  getStatus(): Promise<LicenseStatusResponse> {
    return this.request('get', `/status`, undefined, {
      skipAuth: true,
      skipErrorHandling: true,
    });
  }

  /**
   * Get the unified machine code.
   * GET /console/api/license/machine-code
   */
  getMachineCode(): Promise<MachineCodeResponse> {
    return this.request('get', `/machine-code`, undefined, {
      skipAuth: true,
      skipErrorHandling: true,
    });
  }

  /**
   * Upload a new license file.
   * POST /console/api/license/upload (multipart/form-data, field name "file")
   */
  upload(file: File): Promise<LicenseStatusResponse> {
    const formData = new FormData();
    formData.append('file', file);
    return this.request('post', `/upload`, formData, {
      skipAuth: true,
      skipErrorHandling: true,
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  /**
   * Force the backend to reload the license file from disk.
   * POST /console/api/license/reload
   */
  reload(): Promise<LicenseStatusResponse> {
    return this.request('post', `/reload`, undefined, {
      skipAuth: true,
      skipErrorHandling: true,
    });
  }
}

export const licenseService = new LicenseService();
export default licenseService;
