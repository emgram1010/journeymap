import React, { useState, useRef, useEffect, useCallback } from 'react';
import { 
  Send, 
  Play, 
  RotateCcw, 
  CheckCircle2, 
  CircleDashed, 
  HelpCircle, 
  Info, 
  ChevronRight,
  MessageSquare,
  LayoutGrid,
  Search,
  Settings2,
  X,
  GripHorizontal,
  Edit2,
  Plus,
  Trash2,
  Lock,
  Unlock,
  Bot,
  MessageCircle,
  Share2,
  Paperclip,
  Sparkles,
  AtSign,
  Box,
  Bookmark,
  MousePointer2,
  Folder,
  Pin,
  GitBranch
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { Message, MatrixCell, CellStatus, Stage, Lens } from './types';
import { STAGES as INITIAL_STAGES, LENSES as INITIAL_LENSES } from './constants';

// Mock initial data
const INITIAL_MESSAGES: Message[] = [
  {
    id: '1',
    role: 'ai',
    content: "Welcome to Emgram1010. I'm here to help you map out your expert process. Let's start with Stage 1. Who is the primary customer involved at this point?",
    timestamp: new Date(),
  },
  {
    id: '2',
    role: 'expert',
    content: "In Stage 1, the customer is typically the Regional Operations Manager who is initiating the request.",
    timestamp: new Date(),
  }
];

const INITIAL_CELLS: MatrixCell[] = INITIAL_STAGES.flatMap(stage => 
  INITIAL_LENSES.map(lens => ({
    id: `${stage.id}-${lens.id}`,
    stageId: stage.id,
    lensId: lens.id,
    content: stage.id === 's1' && lens.id === 'customer' ? 'Regional Operations Manager' : '',
    status: stage.id === 's1' && lens.id === 'customer' ? 'confirmed' : 'open' as CellStatus,
    isLocked: false,
  }))
);

export default function App() {
  const [messages, setMessages] = useState<Message[]>(INITIAL_MESSAGES);
  const [inputText, setInputText] = useState('');
  const [cells, setCells] = useState<MatrixCell[]>(INITIAL_CELLS);
  const [stages, setStages] = useState<Stage[]>(INITIAL_STAGES);
  const [lenses, setLenses] = useState<Lens[]>(INITIAL_LENSES);
  const [selectedCellId, setSelectedCellId] = useState<string | null>(null);
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [isChatMode, setIsChatMode] = useState(false); // false = Interview Mode, true = Chat Mode
  const [isQuestionMode, setIsQuestionMode] = useState(true);
  
  const chatEndRef = useRef<HTMLDivElement>(null);
  const mainRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    if (isChatOpen) {
      scrollToBottom();
    }
  }, [messages, isChatOpen]);

  const handleSendMessage = () => {
    if (!inputText.trim()) return;
    
    const newMessage: Message = {
      id: Date.now().toString(),
      role: 'expert',
      content: inputText,
      timestamp: new Date(),
    };
    
    setMessages([...messages, newMessage]);
    setInputText('');

    // Simulate AI response and matrix update
    setTimeout(() => {
      const aiResponse: Message = {
        id: (Date.now() + 1).toString(),
        role: 'ai',
        content: "Got it. I've updated the Customer lens for Stage 1. What is the primary pain point they face during this initiation phase?",
        timestamp: new Date(),
      };
      setMessages(prev => [...prev, aiResponse]);
      
      // Update a cell as a "draft" ONLY if NOT in chat mode
      if (!isChatMode) {
        setCells(prev => prev.map(c => 
          c.stageId === 's1' && c.lensId === 'painpoint' && !c.isLocked
            ? { ...c, content: 'Manual data entry duplication', status: 'draft' } 
            : c
        ));
      }
    }, 1000);
  };

  const selectedCell = cells.find(c => c.id === selectedCellId);

  const updateCellStatus = (id: string, status: CellStatus) => {
    setCells(cells.map(c => c.id === id ? { ...c, status } : c));
  };

  const updateCellContent = (id: string, content: string) => {
    setCells(cells.map(c => c.id === id ? { ...c, content } : c));
  };

  const toggleCellLock = (id: string) => {
    setCells(cells.map(c => c.id === id ? { ...c, isLocked: !c.isLocked } : c));
  };

  const updateStageLabel = (id: string, label: string) => {
    setStages(stages.map(s => s.id === id ? { ...s, label } : s));
  };

  const updateLensLabel = (id: string, label: string) => {
    setLenses(lenses.map(l => l.id === id ? { ...l, label } : l));
  };

  const addStage = () => {
    const newId = `s${Date.now()}`;
    const newStage: Stage = { id: newId, label: `Stage ${stages.length + 1}` };
    setStages([...stages, newStage]);
    
    // Add cells for the new stage
    const newCells: MatrixCell[] = lenses.map(lens => ({
      id: `${newId}-${lens.id}`,
      stageId: newId,
      lensId: lens.id,
      content: '',
      status: 'open',
      isLocked: false
    }));
    setCells([...cells, ...newCells]);
  };

  const removeStage = (id: string) => {
    if (stages.length <= 1) return;
    setStages(stages.filter(s => s.id !== id));
    setCells(cells.filter(c => c.stageId !== id));
    if (selectedCell?.stageId === id) setSelectedCellId(null);
  };

  const addLens = () => {
    const newId = `l${Date.now()}`;
    const newLens: Lens = { id: newId, label: `New Lens ${lenses.length + 1}` };
    setLenses([...lenses, newLens]);
    
    // Add cells for the new lens
    const newCells: MatrixCell[] = stages.map(stage => ({
      id: `${stage.id}-${newId}`,
      stageId: stage.id,
      lensId: newId,
      content: '',
      status: 'open',
      isLocked: false
    }));
    setCells([...cells, ...newCells]);
  };

  const removeLens = (id: string) => {
    if (lenses.length <= 1) return;
    setLenses(lenses.filter(l => l.id !== id));
    setCells(cells.filter(c => c.lensId !== id));
    if (selectedCell?.lensId === id) setSelectedCellId(null);
  };

  return (
    <div className="flex flex-col h-screen overflow-hidden bg-zinc-50 font-sans">
      {/* Header */}
      <header className="h-14 border-b border-zinc-200 bg-white flex items-center justify-between px-6 shrink-0 z-10">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-zinc-900 rounded flex items-center justify-center text-white font-bold text-xs">E</div>
          <h1 className="font-semibold text-sm tracking-tight">Emgram1010 <span className="text-zinc-400 font-normal ml-2">/ New Journey Map</span></h1>
        </div>
        
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1 text-[11px] font-medium text-zinc-500 uppercase tracking-wider">
            <Info className="w-3.5 h-3.5" />
            AI Interviewer available in the sidebar
          </div>
          <div className="h-4 w-px bg-zinc-200 mx-2" />
          <button className="flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-zinc-600 hover:bg-zinc-100 rounded-md transition-colors">
            <Play className="w-3.5 h-3.5" />
            Play Demo
          </button>
          <button className="flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-zinc-600 hover:bg-zinc-100 rounded-md transition-colors">
            <RotateCcw className="w-3.5 h-3.5" />
            Reset Draft
          </button>
        </div>
      </header>

      {/* Main Content */}
      <main ref={mainRef} className="flex-1 flex flex-col overflow-hidden relative">
        
        {/* Journey Map Matrix Section (Now Full Screen) */}
        <section className="flex-1 flex flex-col bg-zinc-100 overflow-hidden relative">
          
          {/* Matrix Controls & Stats */}
          <div className="h-12 border-b border-zinc-200 bg-white flex items-center justify-between px-6 shrink-0">
            <div className="flex items-center gap-6">
              <div className="flex items-center gap-2">
                <LayoutGrid className="w-4 h-4 text-zinc-400" />
                <span className="text-xs font-semibold text-zinc-700 uppercase tracking-tight">Journey Matrix</span>
              </div>
              <div className="flex items-center gap-4 text-[11px] font-medium">
                <div className="flex items-center gap-1.5 text-emerald-600">
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  {cells.filter(c => c.status === 'confirmed').length} Confirmed
                </div>
                <div className="flex items-center gap-1.5 text-amber-600">
                  <CircleDashed className="w-3.5 h-3.5" />
                  {cells.filter(c => c.status === 'draft').length} Drafts
                </div>
                <div className="flex items-center gap-1.5 text-zinc-400">
                  <HelpCircle className="w-3.5 h-3.5" />
                  {cells.filter(c => c.status === 'open').length} Open
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <div className="relative">
                <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-zinc-400" />
                <input type="text" placeholder="Search matrix..." className="pl-8 pr-3 py-1.5 bg-zinc-100 border-none rounded text-xs focus:ring-1 focus:ring-zinc-300 w-48" />
              </div>
              <button className="p-1.5 hover:bg-zinc-100 rounded text-zinc-500">
                <Settings2 className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* The Matrix Grid */}
          <div className="flex-1 overflow-auto p-6">
            <div 
              className="inline-grid border-t border-l border-zinc-200 bg-white shadow-sm rounded-sm"
              style={{ gridTemplateColumns: `160px repeat(${stages.length}, 240px) 48px` }}
            >
              
              {/* Header Row (Stages) */}
              <div className="sticky top-0 z-20 bg-zinc-50 border-b border-r border-zinc-200 p-3 text-[10px] font-bold text-zinc-400 uppercase tracking-wider flex items-center justify-between">
                Lens
              </div>
              {stages.map(stage => (
                <div key={stage.id} className="sticky top-0 z-20 bg-zinc-50 border-b border-r border-zinc-200 p-0 text-[10px] font-bold text-zinc-900 uppercase tracking-wider text-center group relative">
                  <input 
                    type="text"
                    value={stage.label}
                    onChange={(e) => updateStageLabel(stage.id, e.target.value)}
                    className="w-full h-full bg-transparent border-none text-center py-3 focus:bg-white focus:outline-none focus:ring-1 focus:ring-inset focus:ring-zinc-300 transition-colors"
                  />
                  <div className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                    <button onClick={() => removeStage(stage.id)} className="p-0.5 hover:bg-red-50 text-red-400 rounded">
                      <Trash2 className="w-2.5 h-2.5" />
                    </button>
                    <Edit2 className="w-2.5 h-2.5 text-zinc-300" />
                  </div>
                </div>
              ))}
              {/* Add Stage Column */}
              <div className="sticky top-0 z-20 bg-zinc-50 border-b border-r border-zinc-200 flex items-center justify-center">
                <button 
                  onClick={addStage}
                  className="p-1.5 hover:bg-zinc-200 text-zinc-400 rounded transition-colors"
                  title="Add Stage"
                >
                  <Plus className="w-4 h-4" />
                </button>
              </div>

              {/* Data Rows */}
              {lenses.map(lens => (
                <React.Fragment key={lens.id}>
                  {/* First Column (Lenses) */}
                  <div className="bg-zinc-50/50 border-b border-r border-zinc-200 p-0 text-[11px] font-semibold text-zinc-600 flex items-center group relative">
                    <input 
                      type="text"
                      value={lens.label}
                      onChange={(e) => updateLensLabel(lens.id, e.target.value)}
                      className="w-full h-full bg-transparent border-none px-3 py-3 focus:bg-white focus:outline-none focus:ring-1 focus:ring-inset focus:ring-zinc-300 transition-colors"
                    />
                    <div className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                      <button onClick={() => removeLens(lens.id)} className="p-0.5 hover:bg-red-50 text-red-400 rounded">
                        <Trash2 className="w-2.5 h-2.5" />
                      </button>
                      <Edit2 className="w-2.5 h-2.5 text-zinc-300" />
                    </div>
                  </div>
                  
                  {stages.map(stage => {
                    const cell = cells.find(c => c.stageId === stage.id && c.lensId === lens.id)!;
                    const isSelected = selectedCellId === cell.id;
                    
                    return (
                      <div 
                        key={cell.id}
                        onClick={() => setSelectedCellId(cell.id)}
                        className={`
                          min-h-[80px] p-3 border-b border-r border-zinc-200 text-xs transition-all cursor-pointer relative group
                          ${isSelected ? 'bg-sky-100 text-sky-900 ring-2 ring-inset ring-sky-400 z-10' : 'hover:bg-zinc-50'}
                        `}
                      >
                        {cell.content ? (
                          <div className="line-clamp-3">{cell.content}</div>
                        ) : (
                          <div className="text-zinc-300 italic">No data</div>
                        )}
                        
                        {/* Status Indicator */}
                        <div className="absolute bottom-2 right-2 flex items-center gap-1.5">
                          {cell.isLocked && <Lock className={`w-3 h-3 ${isSelected ? 'text-sky-400' : 'text-zinc-400'}`} />}
                          {cell.status === 'confirmed' && <CheckCircle2 className={`w-3 h-3 ${isSelected ? 'text-emerald-600' : 'text-emerald-500'}`} />}
                          {cell.status === 'draft' && <CircleDashed className={`w-3 h-3 ${isSelected ? 'text-amber-600' : 'text-amber-500'}`} />}
                          {cell.status === 'open' && !cell.isLocked && <div className={`w-1.5 h-1.5 rounded-full ${isSelected ? 'bg-sky-400' : 'bg-zinc-200'}`} />}
                        </div>

                        {/* Hover Quick Edit */}
                        {!isSelected && cell.content && (
                          <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
                            <ChevronRight className="w-3 h-3 text-zinc-400" />
                          </div>
                        )}
                      </div>
                    );
                  })}
                  {/* Empty cell for the "Add Stage" column */}
                  <div className="bg-zinc-50/30 border-b border-r border-zinc-200" />
                </React.Fragment>
              ))}

              {/* Add Lens Row */}
              <div className="bg-zinc-50 border-b border-r border-zinc-200 flex items-center justify-center py-2">
                <button 
                  onClick={addLens}
                  className="p-1.5 hover:bg-zinc-200 text-zinc-400 rounded transition-colors"
                  title="Add Lens"
                >
                  <Plus className="w-4 h-4" />
                </button>
              </div>
              {stages.map(s => (
                <div key={`footer-${s.id}`} className="bg-zinc-50/30 border-b border-r border-zinc-200" />
              ))}
              <div className="bg-zinc-50/30 border-b border-r border-zinc-200" />
            </div>
          </div>

          {/* AI Chat Slider (Right Side) */}
          <AnimatePresence>
            {isChatOpen && (
              <motion.div 
                initial={{ x: '100%' }}
                animate={{ x: 0 }}
                exit={{ x: '100%' }}
                transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                className="absolute right-0 top-0 bottom-0 w-96 bg-white border-l border-zinc-200 shadow-2xl z-40 flex flex-col"
              >
                <div className="h-14 border-b border-zinc-200 flex items-center justify-between px-4 shrink-0 bg-zinc-50">
                  <div className="flex items-center gap-3">
                    <div className="flex flex-col">
                      <span className="text-[10px] font-bold text-zinc-900 uppercase tracking-widest leading-none">AI Interviewer</span>
                      <span className="text-[9px] text-zinc-400 font-medium mt-0.5">{isChatMode ? 'Chat Mode' : 'Interview Mode'}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    <button onClick={() => setIsChatOpen(false)} className="p-1.5 hover:bg-zinc-200 rounded text-zinc-400 transition-colors">
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div className="flex-1 overflow-y-auto p-6 space-y-4 bg-white">
                  {messages.map((msg) => (
                    <div key={msg.id} className={`flex ${msg.role === 'ai' ? 'justify-start' : 'justify-end'}`}>
                      <div className={`max-w-[85%] flex gap-2 ${msg.role === 'ai' ? '' : 'flex-row-reverse'}`}>
                        <div className={`w-6 h-6 rounded-full shrink-0 flex items-center justify-center text-[8px] font-bold ${msg.role === 'ai' ? 'bg-zinc-900 text-white' : 'bg-zinc-200 text-zinc-600'}`}>
                          {msg.role === 'ai' ? 'AI' : 'EX'}
                        </div>
                        <div className={`p-3 rounded-xl text-xs leading-relaxed ${msg.role === 'ai' ? 'bg-zinc-100 text-zinc-800' : 'bg-zinc-900 text-white'}`}>
                          {msg.content}
                        </div>
                      </div>
                    </div>
                  ))}
                  <div ref={chatEndRef} />
                </div>

                <div className="p-4 border-t border-zinc-100 bg-zinc-50/80">
                  <div className="space-y-3">
                    <div className="flex flex-wrap gap-1.5">
                      {['Define Stage 2', 'List systems', 'Risks'].map(chip => (
                        <button key={chip} onClick={() => setInputText(chip)} className="px-2 py-1 bg-white border border-zinc-200 rounded-full text-[10px] text-zinc-500 hover:border-zinc-400 transition-colors">
                          {chip}
                        </button>
                      ))}
                    </div>
                    
                    <div className="bg-white border border-zinc-200 rounded-xl overflow-hidden focus-within:ring-2 focus-within:ring-zinc-900/5 focus-within:border-zinc-400 transition-all shadow-sm">
                      {/* Context Bar */}
                      <div className="px-3 py-2 bg-zinc-50/50 border-b border-zinc-100 flex items-center gap-3 overflow-x-auto no-scrollbar">
                        <div className="flex items-center gap-2 shrink-0">
                          <AtSign className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                          <Box className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                          <Bookmark className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                          <MousePointer2 className="w-3.5 h-3.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                        </div>
                        <div className="h-3 w-px bg-zinc-200 shrink-0" />
                        <div className="flex items-center gap-1.5 px-2 py-0.5 bg-zinc-100 rounded-md shrink-0 border border-zinc-200">
                          <Folder className="w-3 h-3 text-zinc-500" />
                          <span className="text-[9px] font-bold text-zinc-600 uppercase tracking-tighter">emgram1010</span>
                        </div>
                        <div className="flex items-center gap-1.5 px-2 py-0.5 bg-zinc-100 rounded-md shrink-0 border border-zinc-200">
                          <Pin className="w-3 h-3 text-zinc-500" />
                          <span className="text-[9px] font-bold text-zinc-600 uppercase tracking-tighter">about.md</span>
                          <X className="w-2.5 h-2.5 text-zinc-400 hover:text-zinc-600 cursor-pointer" />
                        </div>
                      </div>

                      <div className="px-3 pt-3 flex items-start gap-2">
                        {isQuestionMode && (
                          <div className="flex items-center gap-1.5 px-2 py-1 bg-blue-600 text-white rounded-md shrink-0 shadow-sm">
                            <MessageSquare className="w-3 h-3" />
                            <span className="text-[10px] font-bold whitespace-nowrap">Ask a Question</span>
                          </div>
                        )}
                        <textarea 
                          value={inputText}
                          onChange={(e) => setInputText(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' && !e.shiftKey) {
                              e.preventDefault();
                              handleSendMessage();
                            }
                          }}
                          placeholder="Type your message..."
                          rows={2}
                          className="w-full bg-transparent border-none p-0 text-xs focus:ring-0 resize-none min-h-[40px] placeholder:text-zinc-400"
                        />
                      </div>
                      
                      <div className="px-3 py-2 flex items-center justify-between bg-zinc-50/50 border-t border-zinc-100">
                        <div className="flex items-center gap-2">
                          <button 
                            onClick={() => setIsQuestionMode(!isQuestionMode)}
                            className={`p-1.5 rounded-md transition-all ${isQuestionMode ? 'bg-blue-100 text-blue-600' : 'hover:bg-zinc-200 text-zinc-400'}`}
                          >
                            <MessageSquare className="w-3.5 h-3.5" />
                          </button>
                        </div>
                        
                        <div className="flex items-center gap-1.5">
                          <button 
                            onClick={handleSendMessage}
                            disabled={!inputText.trim()}
                            className="p-1.5 bg-zinc-900 text-white rounded-lg hover:bg-zinc-800 disabled:opacity-30 transition-all shadow-sm"
                          >
                            <Send className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Floating AI Toggle Button */}
          <AnimatePresence>
            {!isChatOpen && !selectedCellId && (
              <motion.button 
                initial={{ scale: 0, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                exit={{ scale: 0, opacity: 0 }}
                onClick={() => setIsChatOpen(true)}
                className="absolute bottom-6 right-6 w-14 h-14 rounded-full shadow-xl flex items-center justify-center transition-all z-50 bg-zinc-900 text-white hover:scale-110"
              >
                <MessageSquare className="w-6 h-6" />
                <span className="absolute -top-1 -right-1 w-4 h-4 bg-amber-500 border-2 border-white rounded-full animate-pulse" />
              </motion.button>
            )}
          </AnimatePresence>

          {/* Detail Panel (Docked) */}
          <AnimatePresence>
            {selectedCell && (
              <motion.div 
                initial={{ x: '100%' }}
                animate={{ x: 0 }}
                exit={{ x: '100%' }}
                transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                className="absolute right-0 top-0 bottom-0 w-80 bg-white border-l border-zinc-200 shadow-2xl z-30 flex flex-col"
              >
                <div className="h-12 border-b border-zinc-200 flex items-center justify-between px-4 shrink-0">
                  <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">Cell Detail</span>
                  <button onClick={() => setSelectedCellId(null)} className="p-1 hover:bg-zinc-100 rounded text-zinc-400">
                    <X className="w-4 h-4" />
                  </button>
                </div>
                
                <div className="flex-1 overflow-y-auto p-6 space-y-6">
                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Context</label>
                    <div className="text-xs font-semibold text-zinc-900">
                      {stages.find(s => s.id === selectedCell.stageId)?.label} • {lenses.find(l => l.id === selectedCell.lensId)?.label}
                    </div>
                  </div>

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Content</label>
                    <div className="relative">
                      <textarea 
                        value={selectedCell.content}
                        onChange={(e) => updateCellContent(selectedCell.id, e.target.value)}
                        disabled={selectedCell.isLocked}
                        placeholder="Enter expert knowledge..."
                        className={`w-full h-32 p-3 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-300 resize-none ${selectedCell.isLocked ? 'opacity-60 cursor-not-allowed' : ''}`}
                      />
                      {selectedCell.isLocked && (
                        <div className="absolute inset-0 bg-zinc-50/20 backdrop-blur-[1px] flex items-center justify-center pointer-events-none">
                          <Lock className="w-6 h-6 text-zinc-300" />
                        </div>
                      )}
                    </div>
                  </div>

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Cell Controls</label>
                    <button 
                      onClick={() => toggleCellLock(selectedCell.id)}
                      className={`w-full flex items-center justify-between p-3 rounded border transition-all ${selectedCell.isLocked ? 'bg-zinc-900 border-zinc-900 text-white' : 'bg-white border-zinc-200 text-zinc-700 hover:bg-zinc-50'}`}
                    >
                      <div className="flex items-center gap-3">
                        {selectedCell.isLocked ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
                        <span className="text-xs font-medium">{selectedCell.isLocked ? 'Cell Locked' : 'Cell Unlocked'}</span>
                      </div>
                      <div className={`text-[9px] font-bold uppercase tracking-wider ${selectedCell.isLocked ? 'text-zinc-400' : 'text-zinc-400'}`}>
                        {selectedCell.isLocked ? 'AI Cannot Edit' : 'AI Can Edit'}
                      </div>
                    </button>
                  </div>

                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Verification Status</label>
                    <div className="space-y-2">
                      {[
                        { id: 'confirmed', label: 'Expert Confirmed', icon: CheckCircle2, color: 'text-emerald-600', bg: 'bg-emerald-50' },
                        { id: 'draft', label: 'Draft Inference', icon: CircleDashed, color: 'text-amber-600', bg: 'bg-amber-50' },
                        { id: 'open', label: 'Open Question', icon: HelpCircle, color: 'text-zinc-500', bg: 'bg-zinc-100' },
                      ].map(status => (
                        <button 
                          key={status.id}
                          onClick={() => updateCellStatus(selectedCell.id, status.id as CellStatus)}
                          className={`
                            w-full flex items-center justify-between p-3 rounded border transition-all
                            ${selectedCell.status === status.id 
                              ? `border-${status.id === 'confirmed' ? 'emerald' : status.id === 'draft' ? 'amber' : 'zinc'}-200 ${status.bg}` 
                              : 'border-transparent hover:bg-zinc-50'}
                          `}
                        >
                          <div className="flex items-center gap-3">
                            <status.icon className={`w-4 h-4 ${status.color}`} />
                            <span className="text-xs font-medium text-zinc-700">{status.label}</span>
                          </div>
                          {selectedCell.status === status.id && <div className="w-1.5 h-1.5 rounded-full bg-zinc-900" />}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                <div className="p-4 border-t border-zinc-100 bg-zinc-50">
                  <button 
                    onClick={() => setSelectedCellId(null)}
                    className="w-full py-2 bg-zinc-900 text-white rounded text-xs font-semibold hover:bg-zinc-800 transition-colors"
                  >
                    Save & Close
                  </button>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </section>
      </main>

      {/* Footer / Legend */}
      <footer className="h-8 border-t border-zinc-200 bg-white flex items-center justify-between px-6 shrink-0 text-[10px] text-zinc-400 font-medium">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-emerald-500" />
            Confirmed
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-amber-500" />
            AI Draft
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-zinc-200" />
            Pending
          </div>
        </div>
        <div>
          Last updated: Today at 04:24 PM • Version 1.0.4
        </div>
      </footer>
    </div>
  );
}
