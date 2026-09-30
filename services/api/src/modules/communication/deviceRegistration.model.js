import mongoose from 'mongoose';

export const PUSH_PLATFORMS = ['android', 'ios', 'macos', 'web'];

const deviceRegistrationSchema = new mongoose.Schema(
  {
    userId: { type: String, required: true, trim: true, index: true },
    deviceId: { type: String, required: true, trim: true, maxlength: 120 },
    deviceName: { type: String, trim: true, maxlength: 120, default: '' },
    platform: {
      type: String,
      enum: PUSH_PLATFORMS,
      required: true,
      index: true,
    },
    token: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      maxlength: 4096,
      select: false,
    },
    enabled: { type: Boolean, default: true, index: true },
    lastSeenAt: { type: Date, default: Date.now },
    lastDeliveredAt: Date,
    lastFailureAt: Date,
    lastError: { type: String, trim: true, maxlength: 500, default: '' },
    failureCount: { type: Number, min: 0, default: 0 },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value._id.toString();
        delete value._id;
        delete value.__v;
        delete value.token;
        return value;
      },
    },
  },
);

deviceRegistrationSchema.index(
  { userId: 1, deviceId: 1 },
  { unique: true, name: 'unique_user_device' },
);

export const DeviceRegistrationModel =
  mongoose.models.DeviceRegistration ??
  mongoose.model('DeviceRegistration', deviceRegistrationSchema);
