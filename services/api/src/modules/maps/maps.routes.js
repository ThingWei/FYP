import { Router } from 'express';
import { body, query, matchedData } from 'express-validator';
import { authenticate } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { textInput } from '../../core/inputValidation.js';
import { asyncHandler } from '../../core/asyncHandler.js';
import { env } from '../../config/env.js';
import { mapsAdapter } from '../../integrations/mapsAdapter.js';
import { validCoordinates } from '../../core/location.js';

export const mapsRouter = Router();
mapsRouter.use(authenticate);
mapsRouter.get('/config', (_req, res) => res.json({ success: true, data: {
  enabled: env.mapsMode === 'openstreetmap', tileUrl: env.mapTileUrl,
  attribution: '© OpenStreetMap contributors', searchMode: 'explicit', country: 'MY',
} }));
mapsRouter.get('/search', query('q').custom(textInput).bail().trim().isLength({ min: 2, max: 160 }),
  validate, asyncHandler(async (req, res) => res.json({ success: true,
    data: await mapsAdapter.search(matchedData(req).q) })));
// Explicit lookup only. POST keeps coordinates out of access-log URLs.
mapsRouter.post('/resolve-pin',
  body('coordinates').custom((value) => {
    if (!validCoordinates(value)) throw new Error('Confirm valid map coordinates');
    return true;
  }),
  body('publicPointConfirmed').custom((value) => {
    if (value !== true) throw new Error('Confirm this is a public place before looking up its address');
    return true;
  }), validate, asyncHandler(async (req, res) => res.json({ success: true,
    data: await mapsAdapter.resolvePin(matchedData(req).coordinates) })));
