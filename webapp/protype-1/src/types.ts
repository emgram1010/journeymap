export type CellStatus = 'draft' | 'confirmed' | 'open';

export interface Message {
  id: string;
  role: 'ai' | 'expert';
  content: string;
  timestamp: Date;
}

export interface MatrixCell {
  id: string;
  stageId: string;
  lensId: string;
  content: string;
  status: CellStatus;
  isLocked?: boolean;
  lastUpdated?: Date;
}

export interface Stage {
  id: string;
  label: string;
}

export interface Lens {
  id: string;
  label: string;
}
