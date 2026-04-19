// API Test Script — Tests new tools + transparency via Xano API
const BASE = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:ER4MRRWZ';

async function api(path, method = 'GET', body = null) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`${BASE}${path}`, opts);
  const data = await res.json();
  if (!res.ok) {
    console.error(`❌ ${method} ${path} → ${res.status}`, data);
    return null;
  }
  return data;
}

function assert(label, condition) {
  if (condition) console.log(`  ✅ ${label}`);
  else console.error(`  ❌ FAIL: ${label}`);
}

async function run() {
  console.log('\n=== API TEST: AI PM Tools + Transparency ===\n');

  // Step 1: Create a draft map
  console.log('1️⃣  Creating draft journey map...');
  const draft = await api('/journey_map/create_draft', 'POST', { title: 'API Test Map', status: 'draft' });
  if (!draft) return;
  const mapId = draft.journey_map.id;
  console.log(`   Map ID: ${mapId}`);
  assert('Map created', mapId > 0);

  // Step 2: Load bundle to get initial stages/lenses
  console.log('\n2️⃣  Loading bundle...');
  const bundle = await api(`/journey_map/load_bundle/${mapId}`);
  if (bundle) {
    console.log(`   Stages: ${bundle.stages?.length ?? 'N/A'}, Lenses: ${bundle.lenses?.length ?? 'N/A'}, Cells: ${bundle.cells?.length ?? 'N/A'}`);
    assert('Has stages', (bundle.stages?.length ?? 0) > 0);
    assert('Has lenses', (bundle.lenses?.length ?? 0) > 0);
  }

  // Step 3: Test ai_message with a real user message (field is 'content' not 'user_message')
  console.log('\n3️⃣  Sending ai_message (interview mode)...');
  const aiReply = await api(`/journey_map/${mapId}/ai_message`, 'POST', {
    content: 'Help me map our employee onboarding process. We have 5 stages: offer accepted, pre-boarding, first day, week 1, and 30-day review.',
    mode: 'interview'
  });
  
  if (aiReply) {
    console.log(`   Reply: "${(aiReply.reply || '').substring(0, 100)}..."`);
    console.log(`   Cell updates: ${aiReply.cell_updates?.length ?? 0}`);
    console.log(`   Structural changes: stages=${aiReply.structural_changes?.stages_changed}, lenses=${aiReply.structural_changes?.lenses_changed}`);
    console.log(`   Progress: ${aiReply.progress?.percentage ?? 'N/A'}%`);
    
    // Check transparency fields
    console.log('\n   📊 TRANSPARENCY CHECK:');
    console.log(`   tool_trace present: ${aiReply.tool_trace !== undefined}`);
    console.log(`   tool_trace count: ${aiReply.tool_trace?.length ?? 'N/A'}`);
    console.log(`   thinking present: ${aiReply.thinking !== undefined && aiReply.thinking !== null}`);
    
    if (aiReply.tool_trace?.length > 0) {
      console.log('\n   🔍 Tool Trace:');
      aiReply.tool_trace.forEach((t, i) => {
        console.log(`     ${i+1}. [${t.tool_category}] ${t.tool_name}: ${t.input_summary} → ${t.output_summary}`);
      });
    }
    
    if (aiReply.thinking) {
      console.log(`\n   💭 Thinking: "${aiReply.thinking.substring(0, 200)}..."`);
    }
    
    assert('tool_trace is array', Array.isArray(aiReply.tool_trace));
    assert('tool_trace has entries', (aiReply.tool_trace?.length ?? 0) > 0);
    assert('thinking field exists', aiReply.thinking !== undefined);
  }

  // Step 4: Send a follow-up with content to write
  console.log('\n4️⃣  Sending follow-up with rich content...');
  const reply2 = await api(`/journey_map/${mapId}/ai_message`, 'POST', {
    content: 'The HR coordinator sends the offer letter through DocuSign. The main pain point is that 40% of candidates take more than 3 days to sign. We track time-to-sign as our key metric.',
    mode: 'interview',
    conversation_id: aiReply?.conversation?.id
  });
  
  if (reply2) {
    console.log(`   Reply: "${(reply2.reply || '').substring(0, 100)}..."`);
    console.log(`   Cell updates: ${reply2.cell_updates?.length ?? 0}`);
    console.log(`   Progress: ${reply2.progress?.percentage ?? 'N/A'}%`);
    
    if (reply2.tool_trace?.length > 0) {
      console.log('\n   🔍 Tool Trace:');
      reply2.tool_trace.forEach((t, i) => {
        console.log(`     ${i+1}. [${t.tool_category}] ${t.tool_name}: ${t.input_summary} → ${t.output_summary}`);
      });
    }
    
    assert('Cell updates > 0 (AI wrote content)', (reply2.cell_updates?.length ?? 0) > 0);
    assert('tool_trace has write tool', reply2.tool_trace?.some(t => t.tool_category === 'write'));
  }

  // Step 5: Ask a question (chat mode)
  console.log('\n5️⃣  Asking a question about the map...');
  const reply3 = await api(`/journey_map/${mapId}/ai_message`, 'POST', {
    content: 'What are all the pain points we have identified so far?',
    mode: 'chat',
    conversation_id: aiReply?.conversation?.id
  });
  
  if (reply3) {
    console.log(`   Reply: "${(reply3.reply || '').substring(0, 150)}..."`);
    console.log(`   Cell updates: ${reply3.cell_updates?.length ?? 0}`);
    
    if (reply3.tool_trace?.length > 0) {
      console.log('\n   🔍 Tool Trace:');
      reply3.tool_trace.forEach((t, i) => {
        console.log(`     ${i+1}. [${t.tool_category}] ${t.tool_name}: ${t.input_summary} → ${t.output_summary}`);
      });
    }
    
    assert('No cell updates (question only)', (reply3.cell_updates?.length ?? 0) === 0);
    assert('tool_trace has read tool', reply3.tool_trace?.some(t => t.tool_category === 'read'));
  }

  console.log('\n=== DONE ===\n');
}

run().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
