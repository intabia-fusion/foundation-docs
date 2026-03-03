const puppeteer = require('puppeteer');
const http = require('http');

const BASE_URL = 'http://localhost:8080';

async function runTests() {
  console.log('Starting link verification tests...\n');
  
  // Wait for server to be ready
  await waitForServer();
  
  const browser = await puppeteer.launch({ headless: 'new' });
  const results = {
    total: 0,
    passed: 0,
    failed: 0,
    broken: [],
    timings: []
  };

  try {
    const page = await browser.newPage();
    
    // Navigate to docs page
    const startTime = Date.now();
    const response = await page.goto(`${BASE_URL}/docs/`, { 
      waitUntil: 'networkidle2',
      timeout: 30000 
    });
    const loadTime = Date.now() - startTime;
    
    console.log(`Page load time: ${loadTime}ms`);
    results.timings.push({ url: '/docs/', time: loadTime });
    
    if (response.status() !== 200) {
      throw new Error(`Failed to load /docs/: ${response.status()}`);
    }
    
    // Get all links
    const links = await page.evaluate(() => {
      const anchors = Array.from(document.querySelectorAll('a[href^="/docs/"]'));
      return anchors.map(a => a.href).filter((v, i, a) => a.indexOf(v) === i);
    });
    
    console.log(`Found ${links.length} unique links to test\n`);
    
    // Test each link
    for (const link of links) {
      results.total++;
      const path = new URL(link).pathname;
      
      try {
        const linkStart = Date.now();
        const response = await page.goto(link, { 
          waitUntil: 'networkidle2',
          timeout: 15000 
        });
        const linkTime = Date.now() - linkStart;
        
        if (response.status() === 200) {
          results.passed++;
          console.log(`✓ ${path} (${linkTime}ms)`);
        } else {
          results.failed++;
          results.broken.push({ url: path, status: response.status() });
          console.log(`✗ ${path} - Status: ${response.status()} (${linkTime}ms)`);
        }
      } catch (error) {
        results.failed++;
        results.broken.push({ url: path, error: error.message });
        console.log(`✗ ${path} - Error: ${error.message}`);
      }
    }
    
    // Test static assets
    console.log('\nTesting static assets...');
    const assets = await page.evaluate(() => {
      const scripts = Array.from(document.querySelectorAll('script[src]'));
      const styles = Array.from(document.querySelectorAll('link[rel="stylesheet"]'));
      return [
        ...scripts.map(s => s.src).filter(s => s.includes('/docs/')),
        ...styles.map(s => s.href).filter(s => s.includes('/docs/'))
      ];
    });
    
    for (const asset of assets) {
      const start = Date.now();
      const response = await page.goto(asset, { timeout: 10000 });
      const time = Date.now() - start;
      console.log(`${response.status() === 200 ? '✓' : '✗'} ${new URL(asset).pathname} (${time}ms)`);
    }
    
  } finally {
    await browser.close();
    
    // Print summary
    console.log('\n' + '='.repeat(50));
    console.log('TEST SUMMARY');
    console.log('='.repeat(50));
    console.log(`Total links tested: ${results.total}`);
    console.log(`Passed: ${results.passed}`);
    console.log(`Failed: ${results.failed}`);
    console.log(`Success rate: ${((results.passed / results.total) * 100).toFixed(1)}%`);
    
    if (results.broken.length > 0) {
      console.log('\nBroken links:');
      results.broken.forEach(link => {
        console.log(`  - ${link.url}${link.status ? ` (Status: ${link.status})` : ` (Error: ${link.error})`}`);
      });
    }
    
    // Calculate performance metrics
    const avgTime = results.timings.reduce((a, b) => a + b.time, 0) / results.timings.length;
    const maxTime = Math.max(...results.timings.map(t => t.time));
    const minTime = Math.min(...results.timings.map(t => t.time));
    
    console.log('\n' + '='.repeat(50));
    console.log('PERFORMANCE METRICS');
    console.log('='.repeat(50));
    console.log(`Average load time: ${avgTime.toFixed(0)}ms`);
    console.log(`Fastest: ${minTime}ms`);
    console.log(`Slowest: ${maxTime}ms`);
    
    process.exit(results.failed > 0 ? 1 : 0);
  }
}

async function waitForServer(maxAttempts = 30) {
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const response = await new Promise((resolve, reject) => {
        http.get(`${BASE_URL}/docs/`, res => resolve(res)).on('error', reject);
      });
      if (response.statusCode === 200) {
        console.log('Server is ready!\n');
        return;
      }
    } catch (e) {
      process.stdout.write(`Waiting for server... (${i + 1}/${maxAttempts})\r`);
    }
    await new Promise(r => setTimeout(r, 1000));
  }
  throw new Error('Server failed to start');
}

runTests().catch(error => {
  console.error('Test failed:', error);
  process.exit(1);
});
