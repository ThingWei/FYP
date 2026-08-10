import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { listingModule } from '../modules/listing/index.js';
await mongoose.connect(env.mongoUri);
await listingModule.Model.deleteMany({});
await listingModule.Model.create([{ title: 'Sony Alpha Camera', category: 'Devices & Electronics', dailyPrice: 45, condition: 'Excellent', status: 'active' }, { title: 'Bosch Cordless Drill', category: 'Equipment & Tools', dailyPrice: 20, condition: 'Good', status: 'active' }]);
await mongoose.disconnect(); console.log('Seed complete');

