import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

let server;
let aiClient;

before(async () => {
  server = http.createServer((request, response) => {
    let body = '';
    request.on('data', (chunk) => {
      body += chunk;
    });
    request.on('end', () => {
      const payload = JSON.parse(body);
      response.setHeader('content-type', 'application/json');
      if (request.url === '/verify/item') {
        response.end(JSON.stringify({ received: payload }));
        return;
      }
      if (request.url === '/verify/document') {
        response.end(JSON.stringify({
          accepted: false,
          outcome: 'manual_review',
          confidence: 0.71,
          labels: ['mykad'],
          reasons: ['Administrator confirmation required'],
          adapter: 'opencv-easyocr-spacy-v1',
          model_versions: {},
          quality: {},
          ocr_text: 'SAMPLE',
          extracted_fields: { received: payload.images.length },
          risk_indicators: [],
        }));
        return;
      }
      if (request.url === '/verify/document-frame') {
        response.end(JSON.stringify({
          available: true,
          detected: true,
          ready: true,
          confidence: 0.91,
          guidance: 'Ready to capture',
          quality: {},
          bounding_box: [0.1, 0.2, 0.9, 0.8],
          adapter: 'opencv-document-yolo-v1',
          received: { side: payload.expected_side, validateCapture: payload.validate_capture },
        }));
        return;
      }
      response.end(JSON.stringify([]));
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  process.env.AI_SERVICE_URL = `http://127.0.0.1:${server.address().port}`;
  ({ aiClient } = await import('../src/integrations/aiClient.js'));
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
});

test('passes protected document bytes to the AI contract without fabricating the result', async () => {
  const result = await aiClient.verifyDocument({
    images: [{
      content_base64: Buffer.from('image').toString('base64'),
      content_type: 'image/jpeg',
      filename: 'identity.jpg',
    }],
    documentType: 'mykad',
    profileName: 'Alex Tan',
  });
  assert.equal(result.outcome, 'manual_review');
  assert.equal(result.confidence, 0.71);
  assert.equal(result.extracted_fields.received, 1);
});

test('forwards physical category, subcategory and condition with stored image bytes', async () => {
  const images = [{ content_base64: 'fixture' }];
  const result = await aiClient.verifyItem({ images, category: 'Vehicles',
    subcategory: 'Cars', condition: 'Good', listingType: 'physical' });
  assert.deepEqual(result.received, { images, expected_category: 'Vehicles',
    expected_subcategory: 'Cars', expected_condition: 'Good', expected_type: 'physical' });
  const unavailable = await aiClient.verifyItem({ images: [] });
  assert.equal(unavailable.outcome, 'unavailable');
});

test('returns an explicit unavailable result when no stored bytes exist', async () => {
  const result = await aiClient.verifyDocument({
    images: [],
    documentType: 'passport',
    profileName: 'Alex Tan',
  });
  assert.equal(result.outcome, 'unavailable');
  assert.equal(result.confidence, 0);
});

test('forwards live scanner frames to the KYC-specific detector contract', async () => {
  const result = await aiClient.inspectDocumentFrame({
    contentBase64: Buffer.from('scanner-frame').toString('base64'),
    contentType: 'image/jpeg',
    documentType: 'driving_licence',
  });
  assert.equal(result.ready, true);
  assert.equal(result.guidance, 'Ready to capture');
  assert.equal(result.confidence, 0.91);
});

test('forwards expected MyKad side and final capture validation without dropping fields', async () => {
  const result = await aiClient.inspectDocumentFrame({
    contentBase64: Buffer.from('scanner-frame').toString('base64'),
    contentType: 'image/jpeg', documentType: 'mykad',
    expectedSide: 'back', validateCapture: true,
  });
  assert.deepEqual(result.received, { side: 'back', validateCapture: true });
});
