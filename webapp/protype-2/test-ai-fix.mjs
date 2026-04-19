import { chromium } from 'playwright';

async function testAIMessageFix() {
  console.log('🚀 Starting AI message fix validation...');
  
  const browser = await chromium.launch({ 
    headless: false,
    slowMo: 1000
  });
  
  try {
    const page = await browser.newPage();
    
    // Step 1: Navigate to app
    console.log('📍 Navigating to http://localhost:3002...');
    await page.goto('http://localhost:3002', { 
      waitUntil: 'domcontentloaded',
      timeout: 60000 
    });
    
    // Step 2: Wait for journey matrix
    console.log('⏳ Waiting for journey matrix to load...');
    await page.waitForSelector('[class*="tabulator"]', { timeout: 30000 });
    
    // Step 3: Open chat
    console.log('💬 Opening chat sidebar...');
    const chatBtn = page.locator('button:has(svg.lucide-message-square)').first();
    await chatBtn.waitFor();
    await chatBtn.click();
    
    // Step 4: Wait for chat interface
    console.log('🤖 Waiting for AI interface...');
    await page.waitForSelector('text=AI Interviewer', { timeout: 10000 });
    
    // Step 5: Intercept requests
    console.log('🕵️ Setting up request interception...');
    const requests = [];
    page.on('request', req => {
      if (req.url().includes('/ai_message') && req.method() === 'POST') {
        const postData = req.postDataJSON();
        requests.push(postData);
        console.log('📡 AI request captured:', JSON.stringify(postData, null, 2));
      }
    });
    
    // Step 6: Send message
    console.log('✍️ Sending test message...');
    const textarea = page.locator('textarea[placeholder="Type your message..."]');
    await textarea.fill('help me create a user journey on creating an ai agent driving journey map');
    await textarea.press('Enter');
    
    // Step 7: Wait for response
    console.log('⏳ Waiting for AI response...');
    await page.waitForTimeout(20000);
    
    // Step 8: Check for errors
    const errorCount = await page.locator('text*="Not numeric"').count();
    const errorMessages = await page.locator('text*="ERROR"').count();
    
    console.log('📊 Test Results:');
    console.log(`   • Requests captured: ${requests.length}`);
    console.log(`   • "Not numeric" errors: ${errorCount}`);
    console.log(`   • Error messages: ${errorMessages}`);
    
    if (requests.length > 0 && errorCount === 0) {
      console.log('✅ SUCCESS: AI message sent without "Not numeric" error!');
    } else if (errorCount > 0) {
      console.log('❌ FAILURE: "Not numeric" error still present');
    } else {
      console.log('⚠️ UNKNOWN: No requests captured - check if message was sent');
    }
    
    // Keep browser open for manual inspection
    console.log('🔍 Browser kept open for manual inspection...');
    await page.waitForTimeout(30000);
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    await browser.close();
    console.log('🏁 Validation complete');
  }
}

testAIMessageFix().catch(console.error);
