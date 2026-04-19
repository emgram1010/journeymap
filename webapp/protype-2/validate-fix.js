const { chromium } = require('@playwright/test');

async function validateAIMessageFix() {
  console.log('Starting validation of AI message fix...');
  
  let browser;
  try {
    browser = await chromium.launch({ headless: false });
    const page = await browser.newPage();
    
    // Navigate to the app
    console.log('Navigating to http://localhost:3002...');
    await page.goto('http://localhost:3002', { waitUntil: 'networkidle' });
    
    console.log('Page loaded successfully');
    
    // Wait for the journey matrix to load
    console.log('Waiting for journey matrix to load...');
    await page.waitForSelector('[class*="tabulator"]', { timeout: 30000 });
    
    // Open chat sidebar
    console.log('Opening chat sidebar...');
    const chatToggle = page.locator('button:has(svg.lucide-message-square)').first();
    await chatToggle.waitFor({ timeout: 15000 });
    await chatToggle.click();
    
    // Wait for AI Interviewer to be visible
    await page.waitForSelector('text=AI Interviewer', { timeout: 10000 });
    console.log('Chat sidebar opened successfully');
    
    // Set up request interception to capture AI message requests
    const requests = [];
    page.on('request', request => {
      if (request.url().includes('/ai_message') && request.method() === 'POST') {
        requests.push({
          url: request.url(),
          method: request.method(),
          postData: request.postDataJSON()
        });
      }
    });
    
    // Send a test message
    console.log('Sending test message...');
    const textarea = page.locator('textarea[placeholder="Type your message..."]');
    await textarea.fill('help me create a user journey on creating a ai agent driving journey map');
    await textarea.press('Enter');
    
    // Wait for the response
    console.log('Waiting for AI response...');
    await page.waitForTimeout(15000); // Wait 15 seconds for processing
    
    // Check if we captured any AI message requests
    if (requests.length > 0) {
      console.log('✅ SUCCESS: AI message request was sent');
      console.log('Request details:', JSON.stringify(requests[0], null, 2));
      
      // Check if there are any error messages visible
      const errorElements = await page.locator('text*="Not numeric"').count();
      if (errorElements === 0) {
        console.log('✅ SUCCESS: No "Not numeric" errors found');
      } else {
        console.log('❌ FAILURE: "Not numeric" error still present');
      }
    } else {
      console.log('❌ FAILURE: No AI message requests were captured');
    }
    
    console.log('Validation complete');
    
  } catch (error) {
    console.error('❌ VALIDATION FAILED:', error.message);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

validateAIMessageFix();
