#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <initializer_list>
#include "mpu6050_i2c.h"

static void reset() {
  Wire = FakeWire{};
  Wire.reg[0x75] = 0x68;
  fakeMs = 0;
  stuckSda = stuckScl = false;
  dataReady = true;
}
static void initialize(MPU6050_I2C &m) {
  assert(m.begin());
  assert(!m.ready());
  fakeMs = 99; m.service(fakeMs); assert(!m.ready());
  fakeMs = 100; m.service(fakeMs);
  fakeMs = 130; m.service(fakeMs);
  fakeMs = 230; m.service(fakeMs); assert(m.ready());
}
int main() {
  reset();
  MPU6050_I2C m;
  initialize(m);
  assert(Wire.timeout == 5 && Wire.repeatedStart);
  assert(Wire.reg[0x19] == 19 && Wire.reg[0x1A] == 4);
  assert(Wire.reg[0x1B] == 8 && Wire.reg[0x1C] == 8);
  assert(Wire.reg[0x37] == 0x20 && Wire.reg[0x38] == 1);
  Wire.reg[0x3A] = 1;
  Wire.reg[0x3B] = 0x20; Wire.reg[0x3C] = 0; // +1g
  Wire.reg[0x3D] = 0xe0; Wire.reg[0x3E] = 0; // -1g
  Wire.reg[0x43] = 0x00; Wire.reg[0x44] = 0x83; // +2dps
  MPU6050Data d = {};
  assert(m.readData(d) == MPU6050_I2C::ReadResult::Ok);
  assert(d.ax_g == 1 && d.ay_g == -1 && d.gx_dps == 2);
  dataReady = false;
  assert(m.readData(d) == MPU6050_I2C::ReadResult::NoData);
  dataReady = true; Wire.reg[0x3A] = 0;
  assert(m.readData(d) == MPU6050_I2C::ReadResult::NoData);
  Wire.shortRead = true;
  assert(m.readData(d) == MPU6050_I2C::ReadResult::Error);
  assert(d.ax_g == 1); // Partial transfer never overwrites the caller's sample.
  assert(Wire.available() == 0);
  Wire.shortRead = false; Wire.nack = true;
  assert(m.readData(d) == MPU6050_I2C::ReadResult::Error);
  Wire.nack = false;
  assert(m.begin() && Wire.endCount == 1); // Peripheral recycled on recovery.

  for (int who : {0x00, 0x69, 0x70, 0x71, 0x72, 0x73, 0xff}) {
    reset(); Wire.reg[0x75] = who;
    MPU6050_I2C wrong;
    assert(!wrong.begin());
  }
  reset(); MPU6050_I2C address69(0x69); initialize(address69);
  assert(Wire.lastAddress == 0x69);
  reset(); stuckSda = true; MPU6050_I2C stuck;
  assert(!stuck.begin() && Wire.beginCount == 0);
  reset(); stuckScl = true; assert(!stuck.begin());
  reset(); Wire.beginOk = false; assert(!stuck.begin());
  reset(); Wire.failWrite = 0x6B; MPU6050_I2C fail;
  assert(!fail.begin());
  reset(); MPU6050_I2C badConfig; assert(badConfig.begin());
  fakeMs = 100; badConfig.service(fakeMs);
  Wire.corruptReg = 0x1C;
  fakeMs = 130; badConfig.service(fakeMs);
  assert(badConfig.state() == MPU6050_I2C::State::Failed);
  reset(); MPU6050_I2C recovery;
  fakeMs = UINT32_MAX - 50;
  assert(recovery.begin());
  fakeMs += 100; recovery.service(fakeMs);
  fakeMs += 30; recovery.service(fakeMs);
  fakeMs += 100; recovery.service(fakeMs);
  assert(recovery.ready());
  puts("PASS: MPU identity, rate/range, signed units, short reads, NACK, bus recovery and timer wrap");
}
