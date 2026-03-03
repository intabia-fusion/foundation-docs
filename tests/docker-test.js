const { execSync } = require('child_process');
const http = require('http');

const IMAGE_NAME = 'intabiafusion/platform-docs';

async function runDockerTests() {
  console.log('='.repeat(60));
  console.log('DOCKER IMAGE BUILD AND TEST');
  console.log('='.repeat(60));
  
  // Step 1: Build Docker image
  console.log('\n[1/4] Building Docker image...');
  const buildStart = Date.now();
  
  try {
    const buildOutput = execSync(`docker build -t ${IMAGE_NAME}:test .`, {
      encoding: 'utf8',
      stdio: 'inherit'
    });
  } catch (error) {
    console.error('Build failed:', error.message);
    process.exit(1);
  }
  
  const buildTime = Date.now() - buildStart;
  console.log(`\n✓ Build completed in ${(buildTime / 1000).toFixed(1)}s`);
  
  // Step 2: Get image size
  console.log('\n[2/4] Checking image size...');
  const imageInfo = execSync(`docker images ${IMAGE_NAME}:test --format "{{.Size}}"`, {
    encoding: 'utf8'
  }).trim();
  console.log(`✓ Image size: ${imageInfo}`);
  
  // Step 3: Run container
  console.log('\n[3/4] Starting container...');
  execSync(`docker rm -f platform-docs-test 2>/dev/null || true`);
  execSync(`docker run -d --name platform-docs-test -p 8080:80 ${IMAGE_NAME}:test`);
  
  // Wait for server
  console.log('Waiting for server to be ready...');
  await waitForServer();
  
  // Step 4: Download speed test
  console.log('\n[4/4] Testing download speed...');
  await testDownloadSpeed();
  
  // Cleanup
  console.log('\n[Cleanup] Stopping and removing container...');
  execSync('docker rm -f platform-docs-test');
  
  console.log('\n' + '='.repeat(60));
  console.log('ALL TESTS PASSED ✓');
  console.log('='.repeat(60));
}

async function testDownloadSpeed() {
  const testPaths = [
    '/docs/',
    '/docs/getting-started/introduction-platform/',
    '/docs/task-tracking/creating-issues/'
  ];
  
  console.log('\nDownload Speed Test:');
  console.log('-'.repeat(40));
  
  for (const path of testPaths) {
    const start = Date.now();
    const content = await downloadPage(path);
    const time = Date.now() - start;
    const sizeKB = (content.length / 1024).toFixed(1);
    const speedKbps = (content.length / 1024 / (time / 1000)).toFixed(1);
    
    console.log(`${path}`);
    console.log(`  Size: ${sizeKB} KB, Time: ${time}ms, Speed: ${speedKbps} KB/s`);
  }
}

function downloadPage(path) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 8080,
      path: path,
      method: 'GET'
    };
    
    const req = http.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    });
    
    req.on('error', reject);
    req.setTimeout(30000, () => reject(new Error('Timeout')));
    req.end();
  });
}

async function waitForServer(maxAttempts = 30) {
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const response = await new Promise((resolve, reject) => {
        http.get('http://localhost:8080/docs/', res => resolve(res)).on('error', reject);
      });
      if (response.statusCode === 200) {
        console.log('✓ Server is ready!');
        return;
      }
    } catch (e) {
      process.stdout.write('.');
    }
    await new Promise(r => setTimeout(r, 1000));
  }
  throw new Error('Server failed to start');
}

runDockerTests().catch(error => {
  console.error('Test failed:', error);
  execSync('docker rm -f platform-docs-test 2>/dev/null || true');
  process.exit(1);
});
