



#define MT_ANN   0
#define MT_READ  1
#define MT_WRITE 2
#define MT_EXEC  3
#define MT_QUERY 4
#define MT_MASK  0x0f
#define MT_RESP  0x80

#define OPC_OFF  0
#define RET_OFF  1
#define XID_OFF  2
#define ADDR_OFF 4
#define SIZE_OFF 6
#define DATA_OFF 8
#define PORT    6999
#define BUFLEN  425

uint8_t buf[BUFLEN];

#define b_op   (*(uint8_t *)(buf + OPC_OFF))
#define b_ret  (*(uint8_t *)(buf + RET_OFF))
#define b_xid  (*(uint16_t *)(buf + XID_OFF))
#define b_addr (*(uint16_t *)(buf + ADDR_OFF))
#define b_size (*(uint16_t *)(buf + SIZE_OFF))
#define b_data ((uint8_t *)(buf + DATA_OFF))


#define Z_ERROK 0;
#define Z_ERRNF 1;
