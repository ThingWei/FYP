import axios from 'axios';
import { env } from '../config/env.js';

const client = axios.create({ baseURL: env.aiUrl, timeout: env.aiTimeoutMs });

async function request(path, payload, unavailable) {
  try {
    const response = await client.post(path, payload);
    return response.data;
  } catch (error) {
    return {
      ...unavailable,
      error: error.response?.data?.detail ?? error.message,
    };
  }
}

const unavailableVerification = (reason) => ({
  accepted: false,
  outcome: 'unavailable',
  confidence: 0,
  labels: [],
  reasons: [reason],
  adapter: 'ai-service-unavailable',
  model_versions: {},
  quality: {},
  ocr_text: '',
  extracted_fields: {},
  risk_indicators: [],
});

export const aiClient = {
  async verifyDocument({ images, documentType, profileName }) {
    if (!images?.length) {
      return unavailableVerification('No stored document bytes were available for analysis');
    }
    return request('/verify/document', {
      images,
      expected_type: documentType,
      profile_name: profileName,
    }, unavailableVerification('AI service could not analyse the identity document'));
  },

  async verifyItem({ images, category, listingType }) {
    if (!images?.length) {
      return unavailableVerification('No stored listing-image bytes were available for analysis');
    }
    return request('/verify/item', {
      images,
      expected_category: category,
      expected_type: listingType,
    }, unavailableVerification('AI service could not analyse the item images'));
  },

  recommendItems(payload) {
    return request('/recommend/items', payload, []);
  },

  recommendPrice(payload) {
    return request('/recommend/price', payload, {
      available: false,
      confidence: 0,
      adapter: 'ai-service-unavailable',
      explanation: [],
      similar_listing_average: payload.similar_active_average,
      historical_average: payload.historical_completed_average,
    });
  },
};

