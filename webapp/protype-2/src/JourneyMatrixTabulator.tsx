import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {useNavigate} from 'react-router-dom';
import {TabulatorFull as Tabulator} from 'tabulator-tables';
import 'tabulator-tables/dist/css/tabulator.min.css';
import {cancelScheduledAnimationFrame, scheduleAnimationFrame} from './frameScheduler';
import {
  applyMatrixSearchFilter,
  findMatrixCellIdFromClickTarget,
  formatLensCellMarkup,
  formatMatrixCellMarkup,
  formatStageHeaderMarkup,
  syncSelectedMatrixCellClasses,
  type CellLinkInfo,
} from './journeyMatrixTabulatorHelpers';
import type {MatrixCell, Stage, Lens} from './types';
import {doesPlannedWork} from './stageOwnerModel';

type Props = {
  stages: Stage[];
  lenses: Lens[];
  cells: MatrixCell[];
  selectedCellId: string | null;
  searchTerm: string;
  onSelectCell: (id: string) => void;
  onUpdateLensLabel: (id: string, label: string) => void;
  onUpdateStageLabel: (id: string, label: string) => void;
  onEditLens: (lensId: string) => void;
  onEditStage: (stageId: string) => void;
  // Optional: map of xanoId → link info for breakpoint indicators
  linkedCells?: Map<number, CellLinkInfo>;
  // STAGE-1 (US-STAGE-1-06) — toggles a lens row's does_planned_work override
  onTogglePlannedWork?: (lensId: string) => void;
  // AUTH-1 (US-AUTH-1-04) — stage.key/id → ready, from computeMapReadiness.perStage
  stageReadiness?: Record<string, boolean>;
  // ORD-1 (US-ORD-1-05) — the seam + and the move arrows. Omit all four and the
  // matrix draws neither (read-only use is unchanged).
  // seamIndex: 0 = before the first item, items.length = after the last.
  onInsertStageAt?: (seamIndex: number) => void;
  onMoveStage?: (stageId: string, dir: -1 | 1) => void;
  onInsertLensAt?: (seamIndex: number) => void;
  onMoveLens?: (lensId: string, dir: -1 | 1) => void;
};

export default function JourneyMatrixTabulator({
  stages,
  lenses,
  cells,
  selectedCellId,
  searchTerm,
  onSelectCell,
  onUpdateLensLabel,
  onUpdateStageLabel,
  onEditLens,
  onEditStage,
  linkedCells,
  onTogglePlannedWork,
  stageReadiness,
  onInsertStageAt,
  onMoveStage,
  onInsertLensAt,
  onMoveLens,
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
  const linkedCellsRef = useRef<Map<number, CellLinkInfo> | undefined>(linkedCells);
  const selectedCellIdRef = useRef<string | null>(selectedCellId);
  const onSelectCellRef = useRef(onSelectCell);
  const onUpdateLensLabelRef = useRef(onUpdateLensLabel);
  const onUpdateStageLabelRef = useRef(onUpdateStageLabel);
  const onEditLensRef = useRef(onEditLens);
  const onEditStageRef = useRef(onEditStage);
  const onTogglePlannedWorkRef = useRef(onTogglePlannedWork);
  const onInsertStageAtRef = useRef(onInsertStageAt);
  const onMoveStageRef = useRef(onMoveStage);
  const onInsertLensAtRef = useRef(onInsertLensAt);
  const onMoveLensRef = useRef(onMoveLens);
  // Decided once per render: the formatters read it when they draw.
  const orderingEnabled = Boolean(onInsertStageAt || onMoveStage || onInsertLensAt || onMoveLens);
  const orderingEnabledRef = useRef(orderingEnabled);

  const cellMap = useMemo(
    () => new Map(cells.map((cell) => [`${cell.stageId}:${cell.lensId}`, cell])),
    [cells],
  );

  const tableData = useMemo(
    () =>
      lenses.map((lens, lensIndex) => {
        const row: Record<string, string | boolean | number> = {
          id: lens.id,
          // ORD-1 — row position, so the row header can draw its seams and arrows.
          lensIndex,
          lensCount: lenses.length,
          lensLabel: lens.label,
          lensActorType: lens.actorType ?? '',
          // STAGE-1 (US-STAGE-1-06) — resolved value (override or actor_type default), same rule as stageOwnerModel/readiness.
          lensDoesPlannedWork: doesPlannedWork(lens.actorType ?? null, lens.plannedWorkOverride ?? null),
        };
        stages.forEach((stage) => {
          row[stage.id] = cellMap.get(`${stage.id}:${lens.id}`)?.content ?? '';
        });
        return row;
      }),
    [cellMap, lenses, stages],
  );

  const columnsSignature = useMemo(
    () =>
      stages
        .map((s) => `${s.id}:${s.label}:${s.stageGoal ?? ''}:${s.primaryActorLens ?? ''}:${stageReadiness?.[s.key ?? s.id] ?? ''}`)
        .join('|'),
    [stages, stageReadiness],
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
    selectedCellIdRef.current = selectedCellId;
  }, [selectedCellId]);

  useEffect(() => {
    onSelectCellRef.current = onSelectCell;
  }, [onSelectCell]);

  useEffect(() => {
    onUpdateLensLabelRef.current = onUpdateLensLabel;
  }, [onUpdateLensLabel]);

  useEffect(() => {
    onUpdateStageLabelRef.current = onUpdateStageLabel;
  }, [onUpdateStageLabel]);

  useEffect(() => {
    onEditLensRef.current = onEditLens;
  }, [onEditLens]);

  useEffect(() => {
    onEditStageRef.current = onEditStage;
  }, [onEditStage]);

  useEffect(() => {
    onTogglePlannedWorkRef.current = onTogglePlannedWork;
  }, [onTogglePlannedWork]);

  useEffect(() => {
    onInsertStageAtRef.current = onInsertStageAt;
    onMoveStageRef.current = onMoveStage;
    onInsertLensAtRef.current = onInsertLensAt;
    onMoveLensRef.current = onMoveLens;
    orderingEnabledRef.current = orderingEnabled;
  }, [onInsertStageAt, onMoveStage, onInsertLensAt, onMoveLens, orderingEnabled]);

  useEffect(() => {
    linkedCellsRef.current = linkedCells;
    // Re-render table cells when link data changes
    if (tableRef.current) {
      tableRef.current.getRows().forEach((row) => row.reformat());
    }
  }, [linkedCells]);

  const syncSelectedCellClasses = useCallback((table: Tabulator) => {
    syncSelectedMatrixCellClasses(table as never, cellMapRef.current, selectedCellIdRef.current);
  }, []);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) {
      return;
    }

    const handleClick = (event: MouseEvent) => {
      // ORD-1 (US-ORD-1-05) — seam + and move arrows. Same delegated pattern as
      // the edit/planned-work buttons: the headers are Tabulator markup strings,
      // so there is no React onClick to attach to.
      const target = event.target as HTMLElement;
      const orderBtn = target.closest?.(
        '[data-insert-stage-at], [data-insert-lens-at], [data-move-stage-id], [data-move-lens-id]',
      ) as HTMLButtonElement | null;
      if (orderBtn && container.contains(orderBtn)) {
        event.stopPropagation();
        event.preventDefault();
        if (orderBtn.disabled) {
          return;
        }
        const {insertStageAt, insertLensAt, moveStageId, moveLensId, moveDir} = orderBtn.dataset;
        const dir = moveDir === '-1' ? -1 : 1;
        if (insertStageAt !== undefined) {
          onInsertStageAtRef.current?.(Number(insertStageAt));
        } else if (insertLensAt !== undefined) {
          onInsertLensAtRef.current?.(Number(insertLensAt));
        } else if (moveStageId) {
          onMoveStageRef.current?.(moveStageId, dir);
        } else if (moveLensId) {
          onMoveLensRef.current?.(moveLensId, dir);
        }
        return;
      }

      // Intercept clicks on the stage edit button.
      const stageEditBtn = (event.target as HTMLElement).closest?.('[data-edit-stage-id]') as HTMLElement | null;
      if (stageEditBtn && container.contains(stageEditBtn)) {
        event.stopPropagation();
        const stageId = stageEditBtn.dataset.editStageId;
        if (stageId) {
          onEditStageRef.current(stageId);
        }
        return;
      }

      // Intercept clicks on the lens edit button.
      const editBtn = (event.target as HTMLElement).closest?.('[data-edit-lens-id]') as HTMLElement | null;
      if (editBtn && container.contains(editBtn)) {
        event.stopPropagation();
        const lensId = editBtn.dataset.editLensId;
        if (lensId) {
          onEditLensRef.current(lensId);
        }
        return;
      }

      // Intercept clicks on the planned-work toggle.
      const plannedWorkBtn = (event.target as HTMLElement).closest?.('[data-toggle-planned-work-lens-id]') as HTMLElement | null;
      if (plannedWorkBtn && container.contains(plannedWorkBtn)) {
        event.stopPropagation();
        const lensId = plannedWorkBtn.dataset.togglePlannedWorkLensId;
        if (lensId) {
          onTogglePlannedWorkRef.current?.(lensId);
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

    container.addEventListener('click', handleClick);

    return () => {
      container.removeEventListener('click', handleClick);
    };
  }, []);

  const buildColumns = useCallback(
    (currentStages: Stage[], currentLenses: Lens[], currentStageReadiness?: Record<string, boolean>) => [
      {
        title: 'Lens',
        field: 'lensLabel',
        frozen: true,
        width: 180,
        minWidth: 180,
        headerSort: false,
        formatter: (cell: any) => {
          const rowData = cell.getRow().getData();
          // AUTH-1 — "does planned work" is an actor-role concept. A structural/
          // context row (no actorType — Description, Top Pain Point, Key
          // Variable, ...) isn't an actor at all, so it never gets the toggle.
          return formatLensCellMarkup({
            label: String(cell.getValue() ?? ''),
            actorType: rowData.lensActorType || undefined,
            lensId: String(rowData.id),
            doesPlannedWork: rowData.lensActorType ? Boolean(rowData.lensDoesPlannedWork) : undefined,
            position: orderingEnabledRef.current
              ? {index: Number(rowData.lensIndex), count: Number(rowData.lensCount)}
              : undefined,
          });
        },
      },
      ...currentStages.map((stage, stageIndex) => {
        const ownerLens = stage.primaryActorLens
          ? currentLenses.find((l) => l.key === stage.primaryActorLens || l.id === stage.primaryActorLens)
          : undefined;
        const stageReadinessKey = stage.key ?? stage.id;
        return {
          title: formatStageHeaderMarkup({
            label: stage.label,
            stageGoal: stage.stageGoal,
            primaryActorLens: stage.primaryActorLens,
            primaryActorLabel: ownerLens?.label,
            stageId: stage.id,
            isReady: currentStageReadiness ? currentStageReadiness[stageReadinessKey] : undefined,
            position: orderingEnabledRef.current ? {index: stageIndex, count: currentStages.length} : undefined,
          }),
          field: stage.id,
          width: 240,
          minWidth: 220,
          headerSort: false,
          formatter: (cell: any) => {
            const rowData = cell.getRow().getData();
            const lensId = String(rowData.id);
            const meta = cellMapRef.current.get(`${stage.id}:${lensId}`);
            return formatMatrixCellMarkup({
              content: cell.getValue(),
              meta,
              selectedCellId: selectedCellIdRef.current,
              linkedCells: linkedCellsRef.current,
              actorType: rowData.lensActorType || undefined,
            });
          },
        };
      }),
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
      columns: buildColumns(stages, lenses, stageReadiness),
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
  }, [buildColumns, columnsSignature, renderSignature, stageReadiness, stages, tableData, tableDataSignature]);

  useEffect(() => {
    const table = tableRef.current;
    if (!table || !isTableBuilt) {
      return;
    }

    if (lastColumnsSignatureRef.current === columnsSignature) {
      return;
    }

    table.setColumns(buildColumns(stages, lenses, stageReadiness));
    lastColumnsSignatureRef.current = columnsSignature;
  }, [buildColumns, columnsSignature, isTableBuilt, lenses, stageReadiness, stages]);

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