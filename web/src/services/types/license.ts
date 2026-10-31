// License module types for the Unified License Platform (ULP) v1 format.
// English comments only. Strict TypeScript (no any).

/** Unified status codes defined by the ULP license format spec (section 7). */
export type LicenseCode =
  | 'ok'
  | 'license_grace'
  | 'license_disabled'
  | 'license_not_init'
  | 'license_missing'
  | 'license_malformed'
  | 'license_bad_signature'
  | 'license_expired'
  | 'license_clock_rollback'
  | 'license_machine_mismatch'
  | 'license_product_mismatch'
  | 'license_no_public_key';

/** Decoded license payload (mirrors backend license.Payload). */
export interface LicensePayload {
  license_id: string;
  product: string;
  product_display: string;
  customer: string;
  customer_contact?: string;
  issued_at: string | null;
  /** null means a permanent license. */
  expire_time: string | null;
  grace_days: number;
  machine_code: string;
  instance_id?: string;
  features?: Record<string, unknown>;
  permanent: boolean;
}

/** Unified status body returned by status/upload/reload endpoints. */
export interface LicenseStatusResponse {
  code: string;
  valid: boolean;
  message: string;
  in_grace: boolean;
  remaining_days: number;
  checked_at: string;
  license: LicensePayload | null;
  data?: LicenseStatusResponse;
}

/** Machine code response returned by GET /console/api/license/machine-code. */
export interface MachineCodeResponse {
  machine_code: string;
  code: string;
  valid: boolean;
  message: string;
}
