# MPU6050::RotationDetector

`MPU6050::RotationDetector` detects one full rotation around a selected MPU-6050 axis.
It is intended for bicycle wheel or crank rotation detection on PicoRuby/R2P2, where memory allocation during the sampling loop must be kept small.

The detector uses gyro integration as the primary signal. Accelerometer phase is used only as a low-speed fallback when gyro movement is below the deadband and the acceleration vector is reliable enough.

## Data Required From A Sample

`update(sample)` expects a sample object that responds to these methods:

- `time_ms`: sample timestamp in milliseconds.
- `dt`: seconds since the previous sample.
- `gyro_x`, `gyro_y`, `gyro_z`: angular velocity in degrees per second.
- `accel_x`, `accel_y`, `accel_z`: acceleration in g.
- `accel_saturated?`: optional flag from `MPU6050`; true means accelerometer raw values are near the sensor limit.

`MPU6050#sample_now` returns the MPU object itself, so the detector can read these scalar values without allocating arrays or hashes.

## Axis Selection

The detector is created with an axis:

```ruby
detector = MPU6050::RotationDetector.new(:y, 120, 0)
```

The selected axis decides which gyro channel is integrated:

- `:x` uses `gyro_x`
- `:y` uses `gyro_y`
- `:z` uses `gyro_z`

For accelerometer fallback, the detector calculates a phase angle on the plane perpendicular to the selected axis:

- `:x`: `atan2(accel_y, accel_z)`
- `:y`: `atan2(accel_z, accel_x)`
- `:z`: `atan2(accel_x, accel_y)`

In practice, choose the axis whose `max_gyro_*` value is largest while the wheel or crank is rotating. For example, if `max_gyro_y` is much larger than `max_gyro_x` and `max_gyro_z`, use `AXIS = :y`.

## Detection Flow

Each `update(sample)` call follows this flow:

1. Read `sample.time_ms`.
2. Check whether the accelerometer sample is saturated.
3. Check whether the accelerometer phase is reliable enough.
4. Calculate accelerometer phase delta when usable.
5. Calculate gyro angle delta from `gyro_dps * dt`.
6. Prefer gyro delta when it is above the gyro deadband.
7. Fall back to accelerometer phase delta only when gyro delta is zero and the sample was not skipped.
8. Add the selected delta to the internal accumulated angle.
9. Emit an event when the accumulated angle reaches about one full turn.

The gyro delta is calculated as:

```text
delta_angle_rad = gyro_dps * PI / 180 * dt
```

`delta_angle` is in radians. A complete rotation is approximately `2 * PI`, but the detector uses `6.0` as the threshold and then wraps by `2 * PI`. This slightly early threshold makes event detection less likely to miss a turn due to small integration errors.

When a positive rotation is detected:

- `count` increases by 1.
- `time_ms` is set to the event timestamp.
- `update` returns the detector object.

When a negative rotation is detected:

- `count` decreases by 1.
- `time_ms` is set to the event timestamp.
- `update` returns the detector object.

When no rotation event is detected, `update` returns `nil`.

## Direction And Minimum Period

The constructor arguments are:

```ruby
MPU6050::RotationDetector.new(axis, min_period_ms, direction)
```

- `axis`: `:x`, `:y`, `:z`, or `0`, `1`, `2`.
- `min_period_ms`: minimum time between rotation events.
- `direction`: `0` for both directions, `1` or `:positive` for positive only, `-1` or `:negative` for negative only.

`min_period_ms` rejects physically impossible repeated events. For a bicycle wheel, `120` ms is a practical starting point. For a crank, a larger value may be appropriate.

## Gyro Integration

The selected gyro axis is read by `gyro_value(sample)`.

The gyro delta is ignored when:

- `dt` is `nil` or less than or equal to zero.
- `dt` is larger than `max_dt_ms`.
- selected `gyro_dps` is `nil`.
- absolute `gyro_dps` is lower than `gyro_deadband_dps`.

The default gyro deadband is `3.0` dps. This filters noise while the sensor is stationary.

The default `max_dt_ms` is `250` ms in the library. The verification example uses `50` ms to make USB output delays visible during tuning. If `dt_skipped?` is often true, the loop is too slow or logging is too heavy.

## Accelerometer Phase Fallback

The accelerometer fallback estimates rotation by watching the phase of gravity on the plane perpendicular to the selected axis.

It is used only when:

- the sample is not accelerometer-saturated;
- the phase vector magnitude is at least `accel_phase_min_g`;
- gyro delta is zero after deadband filtering;
- the sample was not skipped due to a large `dt`.

The default `accel_phase_min_g` is `0.25`. Internally the detector compares squared magnitude to avoid calling `Math.sqrt`.

If the phase is not valid:

- `phase_valid?` returns `false`;
- the stored previous phase is reset;
- accelerometer phase delta is not used for that sample.

This reset matters because otherwise the next valid accelerometer sample could create a large false delta from an old phase.

## Saturation Handling

`MPU6050#sample` marks `accel_saturated?` when any raw accelerometer channel is near the configured limit.

When `accel_saturated?` is true:

- `saturated?` returns `true`;
- accelerometer phase is ignored;
- previous accelerometer phase is reset;
- gyro integration can still be used.

This prevents sudden acceleration or vibration from being mistaken for a rotation phase change.

## Debug Values

The detector exposes lightweight scalar readers for tuning:

- `count`: detected rotation count.
- `time_ms`: timestamp of the last emitted event.
- `gyro_dps`: latest selected gyro-axis value.
- `delta_angle`: latest selected angle delta in radians.
- `angle`: current accumulated angle in radians.
- `phase`: latest accelerometer phase in radians.
- `phase_valid?`: whether the current accelerometer phase was usable.
- `saturated?`: whether the current sample was accelerometer-saturated.
- `dt_skipped?`: whether the current sample was ignored because `dt` was too large.

For tuning, the most useful values are:

- `max_gyro_x`, `max_gyro_y`, `max_gyro_z`: choose the largest axis.
- `angle`: should move toward `6.0` or `-6.0` during one rotation.
- `dt_skipped?`: should normally be false.
- `phase_valid?`: useful for diagnosing accelerometer fallback, but gyro detection can work while it is false.

## Configuration Methods

The detector keeps the constructor small for PicoRuby compatibility. Additional settings are changed with setters:

```ruby
detector = MPU6050::RotationDetector.new(:y, 120, 0)
detector.set_gyro_deadband_dps(3.0)
detector.set_max_dt_ms(50)
detector.set_accel_phase_min_g(0.25)
```

`MPU6050#rotation_detector` accepts the same values and applies these setters when available:

```ruby
detector = mpu.rotation_detector(:y, 120, 0, 3.0, 50, 0.25)
```

The verification example calls setters only after checking `respond_to?`, so it can still run when an older `rotation_detector.rb` is present on the board.

## Tuning Procedure

1. Run `examples/mpu_6050_rotation_verify.rb`.
2. Spin the wheel or crank.
3. Check `max_gyro_x`, `max_gyro_y`, and `max_gyro_z`.
4. Set `AXIS` to the largest axis.
5. Check that `gyro_dps` follows the selected axis.
6. Check that `angle_rad` moves toward `6.0` or `-6.0`.
7. If `dt_skip_count` increases, reduce logging or increase `MAX_DT_MS`.
8. If tiny vibrations create events, increase `GYRO_DEADBAND_DPS` or `MIN_PERIOD_MS`.
9. If real rotations are missed, lower `GYRO_DEADBAND_DPS`, confirm the axis, and confirm that `dt_skipped` is false.

## Known Limitations

This detector does not perform full sensor fusion. It does not estimate an absolute orientation with a Kalman filter or quaternion filter. It uses only:

- one selected gyro axis for angle integration;
- accelerometer phase as a fallback;
- simple thresholding and period filtering.

That is intentional for PicoRuby on embedded targets. The implementation avoids keeping history buffers and avoids allocating objects in the sampling loop.
