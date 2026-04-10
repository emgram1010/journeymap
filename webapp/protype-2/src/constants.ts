import { Stage, Lens } from './types';

export const STAGES: Stage[] = [
  {id: 's1', key: 's1', label: 'Stage 1', displayOrder: 1},
  {id: 's2', key: 's2', label: 'Stage 2', displayOrder: 2},
  {id: 's3', key: 's3', label: 'Stage 3', displayOrder: 3},
  {id: 's4', key: 's4', label: 'Stage 4', displayOrder: 4},
  {id: 's5', key: 's5', label: 'Stage 5', displayOrder: 5},
  {id: 's6', key: 's6', label: 'Stage 6', displayOrder: 6},
  {id: 's7', key: 's7', label: 'Stage 7', displayOrder: 7},
  {id: 's8', key: 's8', label: 'Stage 8', displayOrder: 8},
];

export const LENSES: Lens[] = [
  {id: 'description', key: 'description', label: 'Description', displayOrder: 1},
  {id: 'customer', key: 'customer', label: 'Customer', displayOrder: 2},
  {id: 'owner', key: 'owner', label: 'Primary Owner', displayOrder: 3},
  {id: 'supporting', key: 'supporting', label: 'Supporting Roles', displayOrder: 4},
  {id: 'painpoint', key: 'painpoint', label: 'Top Pain Point', displayOrder: 5},
  {id: 'variable', key: 'variable', label: 'Key Variable', displayOrder: 6},
  {id: 'risk', key: 'risk', label: 'Cascade Risk', displayOrder: 7},
  {id: 'trigger', key: 'trigger', label: 'Escalation Trigger', displayOrder: 8},
  {id: 'notifications', key: 'notifications', label: 'Notifications', displayOrder: 9},
  {id: 'systems', key: 'systems', label: 'Systems / Tools', displayOrder: 10},
];
