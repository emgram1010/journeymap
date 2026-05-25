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
  syncSelectedMatrixCellClasses,
  type CellLinkInfo,
} from './journeyMatrixTabulatorHelpers';
import type {MatrixCell, Stage, Lens} from './types';

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
  // Optional: map of xanoId → link info for breakpoint indicators
  linkedCells?: Map<number, CellLinkInfo>;
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
  linkedCells,
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
    () => stages.map((stage) => `${stage.id}:${stage.label}`).join('|'),
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

    container.addEventListener('click', handleClick);

    return () => {
      container.removeEventListener('click', handleClick);
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
          return formatLensCellMarkup({
            label: String(cell.getValue() ?? ''),
            actorType: rowData.lensActorType || undefined,
            lensId: String(rowData.id),
          });
        },
      },
      ...currentStages.map((stage) => ({
        title: stage.label,
        field: stage.id,
        width: 240,
        minWidth: 220,
        headerSort: false,
        editableTitle: true,
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

    table.on('columnTitleChanged', (column: any) => {
      const field = column.getField?.();
      const title = column.getDefinition?.().title;
      if (field && field !== 'lensLabel' && typeof title === 'string') {
        onUpdateStageLabelRef.current(field, title);
      }
    });

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