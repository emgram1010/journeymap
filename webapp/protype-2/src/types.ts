export type CellStatus = 'draft' | 'confirmed' | 'open';

export interface Message {
  id: string;
  role: 'ai' | 'expert';
  content: string;
  timestamp: Date;
}

export interface MatrixCell {
  id: string;
  xanoId?: number;
  journeyCellId?: number;
  journeyMapId?: number;
  stageId: string;
  stageKey?: string;
  stageXanoId?: number;
  lensId: string;
  lensKey?: string;
  lensXanoId?: number;
  content: string;
  status: CellStatus;
  isLocked?: boolean;
  lastUpdated?: Date;
}

export interface Stage {
  id: string;
  key?: string;
  xanoId?: number;
  displayOrder?: number;
  label: string;
}

export interface Lens {
  id: string;
  key?: string;
  xanoId?: number;
  displayOrder?: number;
  label: string;
}
