import { catalogController } from './catalog.controller.js';
import { ProductCatalogModel } from './productCatalog.model.js';
import { catalogRouter } from './catalog.routes.js';
import { catalogService } from './catalog.service.js';

export const catalogModule = {
  Model: ProductCatalogModel,
  service: catalogService,
  controller: catalogController,
  router: catalogRouter,
};
