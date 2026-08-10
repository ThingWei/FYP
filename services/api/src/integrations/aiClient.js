import axios from 'axios';
import { env } from '../config/env.js';
export const aiClient = axios.create({ baseURL: env.aiUrl, timeout: 15000 });

