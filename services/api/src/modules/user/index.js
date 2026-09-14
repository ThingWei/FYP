import { userController } from './user.controller.js';
import { UserModel } from './user.model.js';
import { userRepository } from './user.repository.js';
import { userRouter } from './user.routes.js';
import { userService } from './user.service.js';

export const userModule = {
  Model: UserModel,
  repository: userRepository,
  service: userService,
  controller: userController,
  router: userRouter,
};
