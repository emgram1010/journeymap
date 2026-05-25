
import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {useNavigate} from 'react-router-dom';
import {TabulatorFull as Tabulator} from 'tabulator-tables';
import 'tabulator-tables/dist/css/tabulator.min.css';
import {cancelScheduledAnimationFrame, scheduleAnimationFrame} from './frameScheduler';
import {
  applyMatrixSearchFilter,
  computeLensIssueLevel,
  escapeHtml,
  findMatrixCellIdFromClickTarget,
  formatLensCellMarkup,
  formatMatrixCellMarkup,
  syncSelectedMatrixCellClasses,
  type CellLinkInfo,
} from './journeyMatrixTabulatorHelpers';
import type {MatrixCell, Stage, Lens, CellFlowIssue} from './types';

type Props = {
  stages: Stage[];
  lenses: Lens[];
  cells: MatrixCell[];
  selectedCellId: string | null;
  searchTerm: string;
  onSelectCell: (id: string) => void;
  onUpdateLensLabel: (id: string, label: string) => void;
  onEditStage: (stageId: string) => void;
  onEditLens: (lensId: string) => void;
  // Optional: map of xanoId → link info for breakpoint indicators
  linkedCells?: Map<number, CellLinkInfo>;
  // Optional: map of cellId → flow issue (populated after validate_workflow runs)
  flowIssues?: Map<string, CellFlowIssue>;
  // Optional: called when user clicks "AI Fix" on a flow issue tooltip
  onAiFixCell?: (cellId: string, stageKey: string, lensKey: string, code: string, message: string) => void;
};

export default function JourneyMatrixTabulator({
  stages,
  lenses,
  cells,
  selectedCellId,
  searchTerm,
  onSelectCell,
  onUpdateLensLabel,
  onEditStage,
  onEditLens,
  linkedCells,
  flowIssues,
  onAiFixCell,
}: Props) {
  const navigate = useNavigate();
  const containerRef = useRef<HTMLDivElement | null>(null);
  const tableRef = useRef<Tabulator | null>(null);
  const [isTableBuilt, setIsTableBuilt] = useState(false);
  const lastColumnsSignatureRef = useRef('');
  const lastTableDataSignatureRef = useRef('');
  const lastRenderSignatureRef = useRef('');
  const lastSearchQueryRef = useRef('');
  const redrawFrameRef = useRef<number | null>(null);
  const selectFrameRef = useRef<number | null>(null);
  const highlightFrameRef = useRef<number | null>(null);
  const cellMapRef = useRef<Map<string, MatrixCell>>(new Map());
  const stagesRef = useRef<Stage[]>(stages);
  const lensesRef = useRef<Lens[]>(lenses);
  const linkedCellsRef = useRef<Map<number, CellLinkInfo> | undefined>(linkedCells);
  const flowIssuesRef = useRef<Map<string, CellFlowIssue> | undefined>(flowIssues);
  const selectedCellIdRef = useRef<string | null>(selectedCellId);
  const onSelectCellRef = useRef(onSelectCell);
  const onUpdateLensLabelRef = useRef(onUpdateLensLabel);
  const onEditStageRef = useRef(onEditStage);
  const onEditLensRef = useRef(onEditLens);
  const onAiFixCellRef = useRef(onAiFixCell);
  const tooltipRef = useRef<HTMLDivElement | null>(null);

  const cellMap = useMemo(
    () => new Map(cells.map((cell) => [`${cell.stageId}:${cell.lensId}`, cell])),
    [cells],
  );

  const tableData = useMemo(
    () =>
      lenses.map((lens) => {
        const row: Record<string, string> = {
          id: lens.id,
          lensLabel: lens.label,
          lensActorType: lens.actorType ?? '',
        };
        stages.forEach((stage) => {
          row[stage.id] = cellMap.get(`${stage.id}:${lens.id}`)?.content ?? '';
        });
        return row;
      }),
    [cellMap, lenses, stages],
  );

  const columnsSignature = useMemo(
    () => stages.map((stage) => `${stage.id}:${stage.label}:${stage.stageGoal ?? ''}:${stage.primaryActorLens ?? ''}`).join('|'),
    [stages],
  );

  const tableDataSignature = useMemo(() => JSON.stringify(tableData), [tableData]);

  const renderSignature = useMemo(
    () => JSON.stringify(cells.map((cell) => [cell.id, cell.status, cell.isLocked, cell.content])),
    [cells],
  );

  useEffect(() => {
    cellMapRef.current = cellMap;
  }, [cellMap]);

  useEffect(() => {
    stagesRef.current = stages;
  }, [stages]);

  useEffect(() => {
    lensesRef.current = lenses;
  }, [lenses]);

  useEffect(() => {
    selectedCellIdRef.current = selectedCellId;
  }, [selectedCellId]);

  useEffect(() => {
    onSelectCellRef.current = onSelectCell;
  }, [onSelectCell]);

  useEffect(() => {
    onUpdateLensLabelRef.current = onUpdateLensLabel;
  }, [onUpdateLensLabel]);

  useEffect(() => {
    onEditStageRef.current = onEditStage;
  }, [onEditStage]);

  useEffect(() => {
    onEditLensRef.current = onEditLens;
  }, [onEditLens]);

  useEffect(() => {
    onAiFixCellRef.current = onAiFixCell;
  }, [onAiFixCell]);

  useEffect(() => {
    linkedCellsRef.current = linkedCells;
    // Re-render table cells when link data changes
    if (tableRef.current) {
      tableRef.current.getRows().forEach((row: any) => row.reformat());
    }
  }, [linkedCells]);

  useEffect(() => {
    flowIssuesRef.current = flowIssues;
    // Re-render table cells when flow issue data changes
    if (tableRef.current) {
      tableRef.current.getRows().forEach((row: any) => row.reformat());
    }
  }, [flowIssues]);

  const syncSelectedCellClasses = useCallback((table: Tabulator) => {
    syncSelectedMatrixCellClasses(table as never, cellMapRef.current, selectedCellIdRef.current);
  }, []);

  // ── Tooltip lifecycle ──────────────────────────────────────────────────────
  useEffect(() => {
    const tooltip = document.createElement('div');
    tooltip.className = 'jm-flow-tooltip';
    tooltip.style.display = 'none';
    tooltip.style.position = 'fixed';
    tooltip.style.zIndex = '9999';
    document.body.appendChild(tooltip);
    tooltipRef.current = tooltip;
    return () => {
      if (document.body.contains(tooltip)) document.body.removeChild(tooltip);
      tooltipRef.current = null;
    };
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) {
      return;
    }

    const handleClick = (event: MouseEvent) => {
      // Intercept clicks on the lens edit button before anything else.
      const editBtn = (event.target as HTMLElement).closest?.('[data-edit-lens-id]') as HTMLElement | null;
      if (editBtn && container.contains(editBtn)) {
        event.stopPropagation();
        const lensId = editBtn.dataset.editLensId;
        if (lensId) {
          onEditLensRef.current(lensId);
        }
        return;
      }

      // Breakpoint indicator click — navigate to the linked map
      const linkIndicator = (event.target as Element).closest?.('.jm-link-indicator') as HTMLElement | null;
      if (linkIndicator) {
        event.stopPropagation();
        const targetMapId = linkIndicator.dataset.linkTarget;
        if (targetMapId) navigate(`/maps/${targetMapId}`);
        return;
      }

      const cellId = findMatrixCellIdFromClickTarget(event.target, container);
      if (!cellId) {
        return;
      }

      selectFrameRef.current = scheduleAnimationFrame(window, selectFrameRef.current, () => {
        selectFrameRef.current = null;
        onSelectCellRef.current(cellId);
      });
    };

    // ── Flow issue dot tooltip ────────────────────────────────────────────────
    const showTooltip = (dot: HTMLElement) => {
      const tooltip = tooltipRef.current;
      if (!tooltip) return;
      const severity = dot.dataset.severity ?? 'warning';
      const message = dot.dataset.message ?? '';
      const cellId = dot.dataset.cellId ?? '';
      const code = dot.dataset.code ?? '';
      const stageKey = dot.dataset.stageKey ?? '';
      const lensKey = dot.dataset.lensKey ?? '';
      const isBlocker = severity === 'blocker';
      tooltip.className = `jm-flow-tooltip jm-flow-tooltip--${severity}`;
      tooltip.innerHTML = `
        <div class="jm-flow-tooltip-header">
          <span class="jm-flow-tooltip-icon">${isBlocker ? '🔴' : '🟡'}</span>
          <span class="jm-flow-tooltip-title">Flow ${isBlocker ? 'Blocker' : 'Warning'}</span>
        </div>
        <div class="jm-flow-tooltip-message">${message.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</div>
        <div class="jm-flow-tooltip-actions">
          <button class="jm-flow-tooltip-btn jm-flow-tooltip-btn--ai"
            data-action="ai-fix"
            data-cell-id="${cellId}"
            data-stage-key="${stageKey}"
            data-lens-key="${lensKey}"
            data-code="${code}"
            data-message="${message.replace(/"/g, '&quot;')}"
          >🤖 AI Fix</button>
          <button class="jm-flow-tooltip-btn jm-flow-tooltip-btn--manual"
            data-action="edit-manually"
            data-cell-id="${cellId}"
          >✏️ Edit manually</button>
        </div>
      `;
      tooltip.style.display = 'block';
      const rect = dot.getBoundingClientRect();
      const tooltipW = 240;
      let left = rect.left + rect.width / 2 - tooltipW / 2;
      if (left + tooltipW > window.innerWidth - 8) left = window.innerWidth - tooltipW - 8;
      if (left < 8) left = 8;
      const top = rect.top - 8;
      tooltip.style.left = `${left}px`;
      tooltip.style.top = `${top}px`;
      tooltip.style.transform = 'translateY(-100%)';
    };

    const hideTooltip = () => {
      const tooltip = tooltipRef.current;
      if (tooltip) tooltip.style.display = 'none';
    };

    const showHeaderTooltip = (el: HTMLElement) => {
      const tooltip = tooltipRef.current;
      if (!tooltip) return;
      const kind = el.dataset.headerTooltip;
      const fullText = el.dataset.fullText ?? '';
      const actorType = el.dataset.actorType ?? '';
      if (kind === 'goal') {
        tooltip.className = 'jm-flow-tooltip jm-header-tooltip';
        tooltip.innerHTML = `<div class="jm-flow-tooltip-header"><span class="jm-flow-tooltip-title">Stage Goal</span></div><div class="jm-flow-tooltip-message">${fullText.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</div>`;
      } else if (kind === 'actor') {
        tooltip.className = 'jm-flow-tooltip jm-header-tooltip';
        tooltip.innerHTML = `<div class="jm-flow-tooltip-header"><span style="font-size:14px">&#128100;</span><span class="jm-flow-tooltip-title">Primary Owner</span></div><div class="jm-flow-tooltip-message">${fullText.replace(/</g, '&lt;').replace(/>/g, '&gt;')}${actorType ? ` <span style="opacity:0.6">· ${actorType.replace(/</g, '&lt;')}</span>` : ''}</div>`;
      } else return;
      tooltip.style.display = 'block';
      const rect = el.getBoundingClientRect();
      const tooltipW = 240;
      let left = rect.left + rect.width / 2 - tooltipW / 2;
      if (left + tooltipW > window.innerWidth - 8) left = window.innerWidth - tooltipW - 8;
      if (left < 8) left = 8;
      tooltip.style.left = `${left}px`;
      tooltip.style.top = `${rect.top - 8}px`;
      tooltip.style.transform = 'translateY(-100%)';
    };

    const handleMouseOver = (event: MouseEvent) => {
      const dot = (event.target as Element).closest?.('.jm-flow-issue-dot') as HTMLElement | null;
      if (dot && container.contains(dot)) { showTooltip(dot); return; }
      const headerEl = (event.target as Element).closest?.('.jm-stage-header-hoverable') as HTMLElement | null;
      if (headerEl && container.contains(headerEl)) showHeaderTooltip(headerEl);
    };

    const handleMouseOut = (event: MouseEvent) => {
      const related = event.relatedTarget as Element | null;
      const tooltip = tooltipRef.current;
      if (tooltip && (tooltip.contains(related) || related === tooltip)) return;
      const isLeavingDot = !!(event.target as Element).closest?.('.jm-flow-issue-dot');
      const isLeavingHeader = !!(event.target as Element).closest?.('.jm-stage-header-hoverable');
      if (isLeavingDot || isLeavingHeader) hideTooltip();
    };

    const handleTooltipClick = (event: MouseEvent) => {
      const btn = (event.target as Element).closest?.('[data-action]') as HTMLElement | null;
      if (!btn) return;
      const action = btn.dataset.action;
      if (action === 'edit-manually') {
        const cellId = btn.dataset.cellId;
        if (cellId) onSelectCellRef.current(cellId);
        hideTooltip();
      } else if (action === 'ai-fix') {
        const { cellId = '', stageKey = '', lensKey = '', code = '', message = '' } = btn.dataset;
        onAiFixCellRef.current?.(cellId, stageKey, lensKey, code, message);
        hideTooltip();
      }
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') hideTooltip();
      if ((event.key === 'Enter' || event.key === ' ') && (event.target as Element).classList?.contains('jm-flow-issue-dot')) {
        event.preventDefault();
        showTooltip(event.target as HTMLElement);
      }
    };

    const tooltipEl = tooltipRef.current;
    tooltipEl?.addEventListener('click', handleTooltipClick);
    tooltipEl?.addEventListener('mouseleave', hideTooltip);

    container.addEventListener('click', handleClick);
    container.addEventListener('mouseover', handleMouseOver);
    container.addEventListener('mouseout', handleMouseOut);
    container.addEventListener('keydown', handleKeyDown);

    return () => {
      container.removeEventListener('click', handleClick);
      container.removeEventListener('mouseover', handleMouseOver);
      container.removeEventListener('mouseout', handleMouseOut);
      container.removeEventListener('keydown', handleKeyDown);
      tooltipEl?.removeEventListener('click', handleTooltipClick);
      tooltipEl?.removeEventListener('mouseleave', hideTooltip);
    };
  }, []);

  const buildColumns = useCallback(
    (currentStages: Stage[]) => [
      {
        title: 'Lens',
        field: 'lensLabel',
        frozen: true,
        width: 180,
        minWidth: 180,
        headerSort: false,
        formatter: (cell: any) => {
          const rowData = cell.getRow().getData();
          const lensId = String(rowData.id);
          const issueLevel = computeLensIssueLevel(
            lensId,
            flowIssuesRef.current,
            cellMapRef.current,
            stagesRef.current,
          );
          return formatLensCellMarkup({
            label: String(cell.getValue() ?? ''),
            actorType: rowData.lensActorType || undefined,
            lensId,
            issueLevel,
          });
        },
      },
      ...currentStages.map((stage) => ({
        title: stage.label,
        field: stage.id,
        width: 240,
        minWidth: 220,
        headerSort: false,
        titleFormatter: () => {
          const label = escapeHtml(stage.label);
          const goalHtml = stage.stageGoal
            ? `<div class="jm-stage-goal-subtitle jm-stage-header-hoverable" data-header-tooltip="goal" data-full-text="${escapeHtml(stage.stageGoal)}"><span class="jm-stage-header-label">Goal:</span> ${escapeHtml(stage.stageGoal.length > 80 ? `${stage.stageGoal.slice(0, 80)}\u2026` : stage.stageGoal)}</div>`
            : `<div class="jm-stage-goal-subtitle jm-stage-goal-subtitle--missing">&#9888; No goal set</div>`;
          let actorHtml = '';
          if (stage.primaryActorLens) {
            const actorLens = lensesRef.current.find((l) => l.id === stage.primaryActorLens);
            if (actorLens) {
              const actorLabel = escapeHtml(actorLens.label);
              const actorType = escapeHtml(actorLens.actorType ?? '');
              actorHtml = `<div class="jm-stage-primary-actor jm-stage-header-hoverable" data-header-tooltip="actor" data-full-text="${actorLabel}" data-actor-type="${actorType}">&#128100; <span class="jm-stage-header-label">Owner:</span> ${actorLabel}</div>`;
            }
          }
          return `<div><div>${label}</div>${goalHtml}${actorHtml}</div>`;
        },
        headerClick: (_e: MouseEvent, column: any) => {
          const field = column.getField?.();
          if (field && field !== 'lensLabel') {
            onEditStageRef.current(field);
          }
        },
        formatter: (cell: any) => {
          const rowData = cell.getRow().getData();
          const lensId = String(rowData.id);
          const meta = cellMapRef.current.get(`${stage.id}:${lensId}`);
          return formatMatrixCellMarkup({
            content: cell.getValue(),
            meta,
            selectedCellId: selectedCellIdRef.current,
            linkedCells: linkedCellsRef.current,
            flowIssues: flowIssuesRef.current,
            actorType: rowData.lensActorType || undefined,
          });
        },
      })),
    ],
    [],
  );

  useEffect(() => {
    if (!containerRef.current || tableRef.current) {
      return;
    }

    setIsTableBuilt(false);

    let frameId: number | null = null;

    const table = new Tabulator(containerRef.current, {
      data: tableData,
      columns: buildColumns(stages),
      index: 'id',
      layout: 'fitDataTable',
      height: '100%',
      placeholder: 'No matrix rows configured.',
      resizableRows: false,
      headerVisible: true,
      cellVertAlign: 'middle',
      columnHeaderVertAlign: 'middle',
    });
    tableRef.current = table;
    lastColumnsSignatureRef.current = columnsSignature;
    lastTableDataSignatureRef.current = tableDataSignature;
    lastRenderSignatureRef.current = renderSignature;

    table.on('tableBuilt', () => {
      frameId = window.requestAnimationFrame(() => {
        setIsTableBuilt(true);
      });
    });

    return () => {
      if (frameId !== null) {
        window.cancelAnimationFrame(frameId);
      }
      redrawFrameRef.current = cancelScheduledAnimationFrame(window, redrawFrameRef.current);
      selectFrameRef.current = cancelScheduledAnimationFrame(window, selectFrameRef.current);
      highlightFrameRef.current = cancelScheduledAnimationFrame(window, highlightFrameRef.current);
      setIsTableBuilt(false);
      tableRef.current = null;
      table.destroy();
    };
  }, [buildColumns, columnsSignature, renderSignature, stages, tableData, tableDataSignature]);

  useEffect(() => {
    const table = tableRef.current;
    if (!table || !isTableBuilt) {
      return;
    }

    if (lastColumnsSignatureRef.current === columnsSignature) {
      return;
    }

    table.setColumns(buildColumns(stages));
    lastColumnsSignatureRef.current = columnsSignature;
  }, [buildColumns, columnsSignature, isTableBuilt, stages]);

  useEffect(() => {
    const table = tableRef.current;
    if (!table || !isTableBuilt) {
      return;
    }

    if (lastTableDataSignatureRef.current === tableDataSignature) {
      return;
    }

    void table.setData(tableData).then(() => {
      if (tableRef.current !== table) {
        return;
      }

      lastTableDataSignatureRef.current = tableDataSignature;
      applyMatrixSearchFilter(table, searchTerm, stages);
      syncSelectedCellClasses(table);
    });
  }, [isTableBuilt, searchTerm, stages, syncSelectedCellClasses, tableData, tableDataSignature]);

  useEffect(() => {
    const table = tableRef.current;
    if (!table || !isTableBuilt) {
      return;
    }

    if (lastRenderSignatureRef.current === renderSignature) {
      return;
    }

    redrawFrameRef.current = scheduleAnimationFrame(window, redrawFrameRef.current, () => {
      redrawFrameRef.current = null;
      if (tableRef.current !== table) {
        return;
      }
      table.redraw(true);
      syncSelectedCellClasses(table);
      lastRenderSignatureRef.current = renderSignature;
    });

    return () => {
      redrawFrameRef.current = cancelScheduledAnimationFrame(window, redrawFrameRef.current);
    };
  }, [isTableBuilt, renderSignature, syncSelectedCellClasses]);

  useEffect(() => {
    const table = tableRef.current;
    if (!table || !isTableBuilt) {
      return;
    }

    highlightFrameRef.current = scheduleAnimationFrame(window, highlightFrameRef.current, () => {
      highlightFrameRef.current = null;
      if (tableRef.current !== table) {
        return;
      }

      syncSelectedCellClasses(table);
    });

    return () => {
      highlightFrameRef.current = cancelScheduledAnimationFrame(window, highlightFrameRef.current);
    };
  }, [columnsSignature, isTableBuilt, selectedCellId, syncSelectedCellClasses, tableDataSignature]);

  useEffect(() => {
    const table = tableRef.current;
    if (!table || !isTableBuilt) {
      return;
    }

    const query = searchTerm.trim().toLowerCase();
    if (lastSearchQueryRef.current === query) {
      return;
    }

    applyMatrixSearchFilter(table, searchTerm, stages);
    lastSearchQueryRef.current = query;
  }, [isTableBuilt, searchTerm, stages]);

  return <div ref={containerRef} className="journey-tabulator h-full w-full" />;
}