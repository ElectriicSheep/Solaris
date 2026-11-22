#include "bq76952_emul.h"
#include "bq769x2_registers.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint32_t seq;
static void txn(BqeState *s, uint8_t addr, uint8_t rd, uint8_t reg,
                const uint8_t *data, uint8_t n, uint8_t *resp)
{
    uint8_t req[BQE_I2C_REQ_BYTES]={0};
    ++seq; req[0]=(uint8_t)seq; req[1]=(uint8_t)(seq>>8);
    req[2]=(uint8_t)(seq>>16); req[3]=(uint8_t)(seq>>24);
    req[4]=addr; req[5]=rd; req[6]=reg; req[7]=n;
    if(data && n) memcpy(&req[8],data,n);
    bqe_i2c_transaction_instance(s,req,resp);
}

static void subcmd(BqeState *s, uint16_t command, uint8_t *resp)
{
    uint8_t d[2]={(uint8_t)command,(uint8_t)(command>>8)};
    txn(s,0x08,0,BQ769X2_CMD_SUBCMD_LOWER,d,2,resp);
}

int main(void)
{
    BqeState *a=bqe_create(), *b=bqe_create();
    assert(a && b);
    uint8_t r[BQE_I2C_RESP_BYTES], d[32], zero[BQE_WRITE_BYTES]={0};

    /* Addressing, subcommand-based device ID read and NACK on wrong address. */
    subcmd(a,BQ769X2_SUBCMD_DEVICE_NUMBER,r); assert(r[4]==0);
    txn(a,0x08,1,BQ769X2_SUBCMD_DATA_START,NULL,2,r);
    assert(r[4]==0 && r[5]==2 && r[6]==0x95 && r[7]==0x76);
    txn(a,0x09,1,BQ769X2_CMD_CONTROL_STATUS,NULL,2,r); assert(r[4]==1);

    /* Measurement commands expose quantized cell, stack, and signed current. */
    double v[16],t[9]; for(int k=0;k<16;k++) v[k]=3.7;
    for(int k=0;k<9;k++) t[k]=298.15;
    uint8_t snap[BQE_SNAP_BYTES],fet[2];
    bqe_step_instance(a,0.01,v,-2.0,t,298.15,59.2,59.2,0,zero,snap,fet);
    txn(a,0x08,1,BQ769X2_CMD_VOLTAGE_CELL_1,d,2,r);
    assert(r[4]==0 && r[6]==0x74 && r[7]==0x0E); /* 3700 mV */
    txn(a,0x08,1,BQ769X2_CMD_VOLTAGE_STACK,d,2,r);
    assert(r[4]==0 && r[6]==0x20 && r[7]==0x17); /* 59.2 V, 10 mV units */
    txn(a,0x08,1,BQ769X2_CMD_CURRENT_CC2,d,2,r);
    assert(r[4]==0 && (int16_t)(r[6]|((uint16_t)r[7]<<8))<0);

    /* Data-memory write requires CFGUPDATE and uses the real checksum/length path. */
    subcmd(a,BQ769X2_SUBCMD_SET_CFGUPDATE,r); assert(r[4]==0);
    uint16_t dm=BQ769X2_SET_CONF_DA; uint8_t ptr[2]={(uint8_t)dm,(uint8_t)(dm>>8)};
    txn(a,0x08,0,BQ769X2_CMD_SUBCMD_LOWER,ptr,2,r); assert(r[4]==0);
    uint8_t value=0x09; txn(a,0x08,0,BQ769X2_SUBCMD_DATA_START,&value,1,r); assert(r[4]==0);
    uint8_t cs=(uint8_t)~((ptr[0]+ptr[1]+value)&0xFF), check[2]={cs,5};
    txn(a,0x08,0,BQ769X2_SUBCMD_DATA_CHECKSUM,check,2,r); assert(r[4]==0);
    txn(a,0x08,0,BQ769X2_CMD_SUBCMD_LOWER,ptr,2,r); assert(r[4]==0);
    txn(a,0x08,1,BQ769X2_SUBCMD_DATA_START,d,1,r); assert(r[4]==0 && r[6]==value);

    /* FET subcommand changes only instance A; register/config state is isolated. */
    subcmd(a,BQ769X2_SUBCMD_ALL_FETS_OFF,r); assert(r[4]==0);
    bqe_step_instance(a,0.01,v,0,t,298.15,59.2,59.2,0,zero,snap,fet);
    assert(fet[0]==0 && fet[1]==0);
    txn(b,0x08,1,BQ769X2_CMD_SUBCMD_LOWER,d,2,r);
    assert(r[4]==0 && r[6]==0 && r[7]==0);
    txn(b,0x08,1,BQ769X2_SUBCMD_DATA_START,d,1,r); assert(r[4]==0 && r[6]!=value);

    /* Independent configurable slave address. */
    BqeConfig c; memset(&c,0,sizeof c); c.i2cAddress=0x09; c.shuntMicroOhms=1000;
    bqe_configure_instance(b,&c);
    txn(b,0x08,1,BQ769X2_CMD_CONTROL_STATUS,NULL,2,r); assert(r[4]==1);
    txn(b,0x09,1,BQ769X2_CMD_CONTROL_STATUS,NULL,2,r); assert(r[4]==0);
    bqe_destroy(a); bqe_destroy(b);
    puts("PASS transaction-level I2C: device ID, measurements, data-memory write/readback, subcommand, NACK and instance independence");
    return 0;
}
