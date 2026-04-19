import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  addEdge,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  type Connection,
  MarkerType,
  Panel,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import {useNavigate} from 'react-router-dom';
import {Link2, X, Pencil, Trash2} from 'lucide-react';
import {
  updateJourneyLink,
  deleteJourneyLink,
  type XanoJourneyMap,
  type XanoJourneyLink,
  type JourneyLinkType,
} from './xano';

const LINK_TYPE_LABELS: Record<JourneyLinkType, string> = {
  exception: 'Exception',
  anti_journey: 'Anti-Journey',
  sub_journey: 'Sub-Journey',
};

const LINK_TYPE_COLORS: Record<JourneyLinkType, string> = {
  exception: '#ef4444',
  anti_journey: '#f59e0b',
  sub_journey: '#6366f1',
};

const STATUS_COLORS: Record<string, string> = {
  draft: '#e4e4e7',
  active: '#34d399',
  archived: '#fbbf24',
};

const NODE_WIDTH = 200;
const NODE_HEIGHT = 80;
const STORAGE_KEY = (archId: number) => `arch-graph-positions-${archId}`;

function loadPositions(archId: number): Record<number, {x: number; y: number}> {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY(archId)) ?? '{}') as Record<number, {x: number; y: number}>;
  } catch {
    return {};
  }
}

function savePositions(archId: number, nodes: Node[]) {
  const pos: Record<number, {x: number; y: number}> = {};
  nodes.forEach((n) => { pos[Number(n.id)] = n.position; });
  localStorage.setItem(STORAGE_KEY(archId), JSON.stringify(pos));
}

interface EdgePopoverState {
  linkId: number;
  link: XanoJourneyLink;
  x: number;
  y: number;
}

interface ArchitectureGraphProps {
  architectureId: number;
  maps: XanoJourneyMap[];
  links: XanoJourneyLink[];
  onLinksChange: (links: XanoJourneyLink[]) => void;
}

export default function ArchitectureGraph({architectureId, maps, links, onLinksChange}: ArchitectureGraphProps) {
  const navigate = useNavigate();
  const [edgePopover, setEdgePopover] = useState<EdgePopoverState | null>(null);
  const [editLabel, setEditLabel] = useState('');
  const [editType, setEditType] = useState<JourneyLinkType>('exception');
  const [saving, setSaving] = useState(false);

  const savedPositions = useMemo(() => loadPositions(architectureId), [architectureId]);

  const initialNodes: Node[] = useMemo(() =>
    maps.map((map, i) => {
      const pos = savedPositions[map.id] ?? {x: (i % 3) * 260, y: Math.floor(i / 3) * 140};
      return {
        id: String(map.id),
        position: pos,
        data: {label: map.title ?? 'Untitled', status: map.status},
        style: {
          width: NODE_WIDTH,
          height: NODE_HEIGHT,
          borderRadius: 12,
          border: `2px solid ${STATUS_COLORS[map.status] ?? '#e4e4e7'}`,
          background: '#fff',
          padding: '12px 14px',
          fontSize: 13,
          fontWeight: 600,
          cursor: 'pointer',
          boxShadow: '0 1px 4px rgba(0,0,0,0.08)',
        },
      };
    }),
  [maps, savedPositions]);

  const initialEdges: Edge[] = useMemo(() =>
    links.map((link) => ({
      id: String(link.id),
      source: String(link.source_map),
      target: String(link.target_map),
      label: `${link.label ?? LINK_TYPE_LABELS[link.link_type]}`,
      markerEnd: {type: MarkerType.ArrowClosed, color: LINK_TYPE_COLORS[link.link_type]},
      style: {stroke: LINK_TYPE_COLORS[link.link_type], strokeWidth: 2},
      labelStyle: {fontSize: 11, fontWeight: 500, fill: LINK_TYPE_COLORS[link.link_type]},
      labelBgStyle: {fill: '#fff', fillOpacity: 0.85},
      type: 'smoothstep',
    })),
  [links]);

  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);

  // Sync edges when links change externally
  useEffect(() => {
    setEdges(initialEdges);
  }, [links, setEdges, initialEdges]);

  // Sync nodes when maps change externally
  useEffect(() => {
    setNodes((prev) =>
      maps.map((map, i) => {
        const existing = prev.find((n) => n.id === String(map.id));
        const pos = existing?.position ?? savedPositions[map.id] ?? {x: (i % 3) * 260, y: Math.floor(i / 3) * 140};
        return {
          id: String(map.id),
          position: pos,
          data: {label: map.title ?? 'Untitled', status: map.status},
          style: existing?.style ?? {
            width: NODE_WIDTH, height: NODE_HEIGHT, borderRadius: 12,
            border: `2px solid ${STATUS_COLORS[map.status] ?? '#e4e4e7'}`,
            background: '#fff', padding: '12px 14px', fontSize: 13, fontWeight: 600,
            cursor: 'pointer', boxShadow: '0 1px 4px rgba(0,0,0,0.08)',
          },
        };
      }),
    );
  }, [maps, savedPositions, setNodes]);

  const onNodeDragStop = useCallback((_: React.MouseEvent, _node: Node, newNodes: Node[]) => {
    savePositions(architectureId, newNodes);
  }, [architectureId]);

  const onNodeClick = useCallback((_: React.MouseEvent, node: Node) => {
    navigate(`/maps/${node.id}`);
  }, [navigate]);

  const onEdgeClick = useCallback((event: React.MouseEvent, edge: Edge) => {
    event.stopPropagation();
    const link = links.find((l) => String(l.id) === edge.id);
    if (!link) return;
    const rect = (event.target as HTMLElement).closest('svg')?.getBoundingClientRect();
    setEdgePopover({linkId: link.id, link, x: event.clientX - (rect?.left ?? 0), y: event.clientY - (rect?.top ?? 0)});
    setEditLabel(link.label ?? '');
    setEditType(link.link_type);
  }, [links]);

  const handleSaveLink = async () => {
    if (!edgePopover) return;
    setSaving(true);
    try {
      const updated = await updateJourneyLink(edgePopover.linkId, {link_type: editType, label: editLabel.trim() || undefined});
      onLinksChange(links.map((l) => (l.id === updated.id ? updated : l)));
      setEdgePopover(null);
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteLink = async () => {
    if (!edgePopover) return;
    setSaving(true);
    try {
      await deleteJourneyLink(edgePopover.linkId);
      onLinksChange(links.filter((l) => l.id !== edgePopover.linkId));
      setEdgePopover(null);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="relative w-full h-[calc(100vh-200px)] rounded-xl border border-zinc-200 overflow-hidden bg-zinc-50">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeDragStop={onNodeDragStop}
        onNodeClick={onNodeClick}
        onEdgeClick={onEdgeClick}
        fitView
        fitViewOptions={{padding: 0.3}}
        deleteKeyCode={null}
      >
        <Background gap={20} size={1} color="#e4e4e7" />
        <Controls />
        <MiniMap nodeColor={(n) => STATUS_COLORS[(n.data as {status: string}).status] ?? '#e4e4e7'} />
        {links.length === 0 && (
          <Panel position="top-center">
            <div className="flex items-center gap-2 px-4 py-2 bg-white border border-zinc-200 rounded-xl shadow-sm text-xs text-zinc-400">
              <Link2 className="w-3.5 h-3.5" />
              No links yet — use "Add Link →" from a map tile in Grid view to connect maps
            </div>
          </Panel>
        )}
      </ReactFlow>

      {/* Edge edit popover */}
      {edgePopover && (
        <div className="absolute z-30 bg-white border border-zinc-200 rounded-xl shadow-xl p-4 w-56"
          style={{left: edgePopover.x + 8, top: edgePopover.y + 8}}>
          <div className="flex items-center justify-between mb-3">
            <p className="text-xs font-semibold text-zinc-700">Edit link</p>
            <button onClick={() => setEdgePopover(null)} className="p-1 text-zinc-400 hover:text-zinc-600"><X className="w-3.5 h-3.5" /></button>
          </div>
          <div className="space-y-2 mb-3">
            <select value={editType} onChange={(e) => setEditType(e.target.value as JourneyLinkType)}
              className="w-full px-2 py-1.5 text-xs border border-zinc-200 rounded-lg focus:outline-none">
              {(Object.keys(LINK_TYPE_LABELS) as JourneyLinkType[]).map((t) => (
                <option key={t} value={t}>{LINK_TYPE_LABELS[t]}</option>
              ))}
            </select>
            <input value={editLabel} onChange={(e) => setEditLabel(e.target.value)} placeholder="Label (optional)"
              className="w-full px-2 py-1.5 text-xs border border-zinc-200 rounded-lg focus:outline-none" />
          </div>
          <div className="flex gap-2">
            <button onClick={() => void handleSaveLink()} disabled={saving}
              className="flex-1 py-1.5 text-xs bg-indigo-600 text-white rounded-lg font-medium hover:bg-indigo-700 disabled:opacity-60 flex items-center justify-center gap-1">
              <Pencil className="w-3 h-3" />Save
            </button>
            <button onClick={() => void handleDeleteLink()} disabled={saving}
              className="flex-1 py-1.5 text-xs bg-rose-50 text-rose-600 border border-rose-200 rounded-lg font-medium hover:bg-rose-100 disabled:opacity-60 flex items-center justify-center gap-1">
              <Trash2 className="w-3 h-3" />Remove
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
