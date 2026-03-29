import { Stage, Lens } from './types';

export const STAGES: Stage[] = [
  { id: 's1', label: 'Stage 1' },
  { id: 's2', label: 'Stage 2' },
  { id: 's3', label: 'Stage 3' },
  { id: 's4', label: 'Stage 4' },
  { id: 's5', label: 'Stage 5' },
  { id: 's6', label: 'Stage 6' },
  { id: 's7', label: 'Stage 7' },
  { id: 's8', label: 'Stage 8' },
];

export const LENSES: Lens[] = [
  { id: 'description', label: 'Description' },
  { id: 'customer', label: 'Customer' },
  { id: 'owner', label: 'Primary Owner' },
  { id: 'supporting', label: 'Supporting Roles' },
  { id: 'painpoint', label: 'Top Pain Point' },
  { id: 'variable', label: 'Key Variable' },
  { id: 'risk', label: 'Cascade Risk' },
  { id: 'trigger', label: 'Escalation Trigger' },
  { id: 'notifications', label: 'Notifications' },
  { id: 'systems', label: 'Systems / Tools' },
];
