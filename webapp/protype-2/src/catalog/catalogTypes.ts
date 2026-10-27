// CAT-1 — Shared shapes for the item-type and method catalogs. Mirrors the
// two new tables (static/tables/135_item_type.xs, 136_method.xs) and the
// catalog/* API responses.

export type CatalogUnit = 'each' | 'set' | 'pair';

export interface ItemType {
  id: number;
  account_id: number;
  key: string;
  label: string;
  unit: CatalogUnit;
  default_method_id: number;
  size_label: string;
  external_ref: string;
  is_active: boolean;
  created_at: number;
  updated_at: string | null;
}

export interface CatalogMethod {
  id: number;
  account_id: number;
  key: string;
  label: string;
  sub_journey_map_id: number;
  role_id: number;
  is_active: boolean;
  created_at: number;
  updated_at: string | null;
}
