#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <arpa/inet.h>
#include <sys/time.h>
#include <time.h>
#include <errno.h>
#include <editline/readline.h>
#include <editline/history.h>
#include "bounce.h"

#define WS      " \n\t"
#define INETZ   sizeof(struct sockaddr_in)
#define BUFLEN  425
#define PTIME   15

int sd;
struct sockaddr_in laddr;
struct sockaddr_in raddr;
uint8_t buf[BUFLEN];
uint8_t obuf[BUFLEN];
uint8_t tbuf[BUFLEN];

struct db_entry {
    int flag;
    struct sockaddr_in addr;
    int cap;
    char name[16];
    time_t time;
};

#define DF_EMPTY 0
#define DF_IFFY  1
#define DF_USED  2


#define MT_ANN   0
#define MT_READ  1
#define MT_WRITE 2
#define MT_EXEC  3
#define MT_MASK  0x0f
#define MF_RESP  0x80

#define DBNUM    16

struct db_entry db[DBNUM];

int conn = -1;

#define ARGBYTE(address) dasmb(address)
#define ARGWORD(address) dasmw(address)
#define OPCODE(address) dasmb(address)

uint16_t base;

uint8_t dasmb(uint16_t add)
{
    return tbuf[add-base];
}

uint16_t dasmw(uint16_t add)
{
    return (tbuf[add-base] << 8) | (tbuf[add-base+1]);
}

#include "dasm09.h"


/* Add a client to the database */
void db_add(struct sockaddr_in *addr)
{
    int x;
    /* don't add if already in database */
    for (x = 0; x < DBNUM; x++){
	if (db[x].flag != DF_EMPTY &&
	    db[x].addr.sin_addr.s_addr == addr->sin_addr.s_addr)
	    goto out;
    }
    /* add to first free db entry */
    for (x = 0; x < DBNUM; x++){
	if (db[x].flag == DF_EMPTY){
	    memcpy(&db[x].addr, addr, sizeof(struct sockaddr_in));
	    db[x].cap = 0;
	    goto out;
	}
    }
  out:
    db[x].time = time(NULL) + PTIME;
    db[x].flag = DF_USED;
}



/* print a list of zombies in the database */
void db_list(void)
{
    int x;
    for (x = 0; x < DBNUM; x++) {
	if (db[x].flag != DF_EMPTY){
	    printf("%c[%d] %s ", x == conn ? '*' : ' ',
		   x, inet_ntoa(db[x].addr.sin_addr) );
	    printf("%c\n", (db[x].flag == DF_IFFY) ? '?' : ' ');
	}
    }
}


/* set certain zombie client as our target */
void do_connect(void)
{
    int x;
    char *p;

    p = strtok(NULL,WS);
    if (!p) {
	fprintf(stderr,"error: number expected\n");
	return;
    }
    x = strtol(p,NULL,10);
    if (x < 0 || x >= DBNUM ){
	fprintf(stderr,"error: connection number out of range.\n");
	return;
    }
    if (db[x].flag != DF_USED){
	fprintf(stderr,"error: no such machine.\n");
	return;
    }
    conn = x;
}


/* send a packet and wait for matching answer */
/*   flag = packet type to wait for */
/*   returns -1 on error, 0 ok. */
int send_trans(int len, int flag)
{
    struct timeval tm;
    int retry = 3;
    int ret;
    int x;
  
    while (retry--) {
	sendto(sd,obuf,len,0,
	       (struct sockaddr *)&db[conn].addr,
	       sizeof(struct sockaddr_in));
	tm.tv_sec = 1;
	tm.tv_usec = 0;
	ret = setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, &tm, sizeof(struct timeval));
	x = sizeof(struct sockaddr_in);
	ret = recvfrom(sd,buf,BUFLEN,0,
		       (struct sockaddr *)&raddr, &x);
	// todo: add announcements here
	if (ret < 0){
	    if (errno == EAGAIN){
		continue;
	    }
	    perror("recv");
	    exit(1);
	}
	if ((buf[0] & MT_MASK) == flag)
	    return 0;
    }
    return -1;
}


int send_read(uint8_t *abuf, uint16_t addr, uint16_t len) {
    uint8_t *p = obuf;
    memset(obuf, 0, BUFLEN);
    *p++ = MT_READ;
    *p++ = 0;
    *p++ = 0;
    *p++ = addr >> 8;
    *p++ = addr & 0xff;
    *p++ = len >> 8;
    *p++ = len & 0xff;
    if (send_trans(p - obuf, MT_READ))
	return -1;
    memcpy(abuf, buf + 7, len);
    return 0;
}


int send_write_ll(uint8_t *abuf, uint16_t addr, uint16_t len) {
    uint8_t *p = obuf;
    memset(obuf, 0, BUFLEN);
    *p++ = MT_WRITE;
    *p++ = 0;
    *p++ = 0;
    *p++ = addr >> 8;
    *p++ = addr & 0xff;
    *p++ = len >> 8;
    *p++ = len & 0xff;
    memcpy(p, abuf, len);
    p += len;
    if (send_trans(p - obuf, MT_WRITE))
	return -1;
    return 0;
}

int send_write(uint8_t *abuf, uint16_t addr, uint16_t len) {
    int todo = len;
    int l;
    while (todo){
	l = BUFLEN < todo ? BUFLEN : todo;
	if (send_write_ll(abuf, addr, l))
	    return -1;
	abuf += l;
	addr += l;
	todo -= l;
    }
    return 0;
}

int send_exec(uint16_t addr){
    uint8_t *p = obuf;
    memset(obuf, 0, BUFLEN);
    *p++ = MT_EXEC;
    *p++ = 0;
    *p++ = 0;
    *p++ = addr >> 8;
    *p++ = addr & 0xff;
    *p++ = 0;
    *p++ = 0;
    return send_trans(p - obuf, MT_EXEC);
}


/* disassemble memory */
void do_dasm(void)
{
    int x;
    uint8_t *p;
    int ret;
    char d[80];
    int l;
    int i;
  
    p = strtok(NULL,WS);
    if (!p) {
	fprintf(stderr,"error: address expected.\n");
	return;
    }
    x = strtol(p, NULL, 16);
    if (x < 0 || x >= 65536) {
	fprintf(stderr,"error: number out of range.\n");
	return;
    }
    p = strtok(NULL, WS);
    l = p ? strtol(p,NULL,16) : 0x30; 
    if (send_read(tbuf, x, l)){
	fprintf(stderr,"error: command timeout.\n");
	return;
    }
    base = x;
    while (x < l + base){
	printf("%.4x  ", x);
	i = ret = Dasm(d,x);
	for (i = 0; i < ret; i++)
	    printf("%.02x", dasmb(x+i));
	i = 4 - ret;
	while(i--)
	    printf("  ");
	x += ret;
	printf(" %s\n",d);
    }
}

uint8_t printable(uint8_t c)
{
    if ( c < 0x20 || c > 0x7e ) return '.';
    return c;
}

/* dump memory from our target client */
void do_dump(void)
{
    int x;
    uint8_t *p;
    int ret;
    int l;
    int i;
    int j;
  
  
    p = strtok(NULL,WS);
    if (!p) {
	fprintf(stderr,"error: address expected.\n");
	return;
    }
    x = strtol(p, NULL, 16);
    if (x < 0 || x >= 65536) {
	fprintf(stderr,"error: number out of range.\n");
	return;
    }
    p = strtok(NULL,WS);
    l = p ? strtol(p,NULL,16) : 0x40;
  
    if (send_read(tbuf, x, l)){
	fprintf(stderr,"error:command timeout.\n");
	return;
    }
    for (j = 0; j < l; j += 16) {
	printf("\n%.4x  ", x);
	x = (x + 16) & 0xffff;
	for (i = 0; i < 16; i++){
	    if (j+i < l)
		printf("%.2x ", tbuf[j+i]);
	    else
		printf("   ");
	}
	for (i = 0; i < 16; i++){
	    if (j+i < l)
		printf("%c", printable(tbuf[j+i]));
	}
    }    
    printf("\n");
}

void do_poke(void)
{
    int a;
    int x;
    int l;
    int len = 0;
    uint8_t *p=tbuf;
    char *s;

    s = strtok(NULL, WS);
    if (!s){
	fprintf(stderr, "error: address expected\n");
	return;
    }
    a = strtol(s, NULL, 16);
    a &= 0xffff;
    while (1){
	s = strtok(NULL, WS);
	if (!s) break;
	x = strtol(s,NULL, 16);
	*p++ = x & 0xff;
	l++;
    }
    if (send_write(tbuf,a,l)){
	fprintf(stderr,"error: command timeout\n");
	return;
    }
    printf("ok\n");
}


void do_exec(void)
{
    int a;
    int x;
    uint8_t *p;
    char *s;

    s = strtok(NULL, WS);
    if (!s){
	fprintf(stderr, "error: address expected\n");
	return;
    }
    a = strtol(s, NULL, 16);
    a &= 0xffff;
    if (send_exec(a)){
	fprintf(stderr,"error: command timeout\n");
	return;
    }
    printf("ok\n");
}


void do_reboot(void)
{
    uint8_t c[2] = { 0, 0 };
    uint16_t *a = (uint16_t *)c;
    if (
	send_write( c, 0x71, 1) ||
	send_read( c, 0xfffe, 2) ||
	send_exec(ntohs(*a))
	) {
	fprintf(stderr,"error: command timeout\n");
	return;
    }
    printf("ok\n");
}

void do_probe(void)
{
    uint8_t c[2];
    if (send_read(c, 0xfffc, 2)) {
	fprintf(stderr,"error: command timeout\n");
	return;
    }
    if (c[1] == 0xfe) {
	printf("CoCo3");
    }
    else
	printf("CoCo2");
    printf("\n");
}


/* load a fuzix bin */
int loadf(char *filename, char *cmdline)
{
    uint8_t h[5];
    int ret;
    int len;
    int addr;
    int todo;
    int l;
    uint8_t aa;
    int room;
    int offset;
    uint8_t saved_mmu;
    uint16_t exec_addr;

    /* we need to check if client is a coco3! */
    /* we also should calculate the needed bank */

    FILE *f = fopen(filename, "r");
    if (!f) {
	perror("fopen");
	return -1;
    }

    if(send_read(&saved_mmu,0xffa1,1))
	return -1;

    /* load kernel to physical address 0 */
    ret = fread(h, 5, 1, f);
    len = ntohs(*((uint16_t *)(h+1)));
    addr = ntohs(*((uint16_t *)(h+3)));

    while (!h[0]){
	printf("*%.04x %.04x\n", addr, len);
	todo = len;
	while(todo){
	    aa = addr >> 13;
	    offset = addr & 0x1fff;
	    room = 0x2000 - offset;
	    if (send_write_ll(&aa, 0xffa1,1))
		return -1;
	    l = BUFLEN < todo ? BUFLEN : todo;
	    l = l < room ? l : room;
	    printf("%.02x %.04x %.04x %.04x\n", aa, offset, l,0x2000+offset);

	    fread(tbuf, l, 1, f);
	    if (send_write_ll(tbuf, 0x2000+offset, l))
		return -1;
	    addr += l;
	    todo -= l;
	}
	ret = fread(h, 5, 1, f);
	len = ntohs(*((uint16_t *)(h+1)));
	addr = ntohs(*((uint16_t *)(h+3)));
    }
    exec_addr = htons(addr);
    fclose(f);
    /* copy bounce routine down */
    if (send_write((uint8_t *)&exec_addr,0x4000,2) ||
	send_write(bounce,0x4002,bounce_len) )
	return -1;
    /* copy kernel's commandline to 0x88 */
    h[0] = 0;
    if (send_write(h, 0xffa1, 1) ||
	send_write(cmdline, 0x2088, strlen(cmdline)+1) ||
	send_write(&saved_mmu, 0xffa1, 1) ) {
	return -1;
    }
    return send_exec(0x4000);
}


int load(char *filename)
{
    uint8_t h[5];
    int ret;
    int len;
    int addr;
    int todo;
    int l;
  
    FILE *f = fopen(filename, "r");
    if (!f) {
	perror("fopen");
	return -1;
    }

    ret = fread(h, 5, 1, f);
    len = ntohs(*((uint16_t *)(h+1)));
    addr = ntohs(*((uint16_t *)(h+3)));
    while (!h[0]){
	printf("%.04x %.04x\n", addr, len);
	todo = len;
	while(todo){
	    l = BUFLEN < todo ? BUFLEN : todo;
	    fread(tbuf, l, 1, f);
	    if (send_write_ll(tbuf, addr, l))
		return -1;
	    addr += l;
	    todo -= l;
	}
	ret = fread(h, 5, 1, f);
	len = ntohs(*((uint16_t *)(h+1)));
	addr = ntohs(*((uint16_t *)(h+3)));
    }
    printf("exec: %.04x\n", addr);
    fclose(f);
    return 0;
}


// load a fuzix image
void do_loadf(void)
{
    char *p;
    char *c;

    p = strtok(NULL, WS);
    if (!p) {
	fprintf(stderr,"error: filename expected.\n");
	return;
    }
    c = strtok(NULL, "\n");
    if(loadf(p, c))
	fprintf(stderr,"error: command timeout.\n");
}


// do a simple .bin load
void do_load(void)
{
    char *p;

    p = strtok(NULL, WS);
    if (!p) {
	fprintf(stderr,"error: filename expected.\n");
	return;
    }
    if(load(p))
	fprintf(stderr,"error: command timeout.\n");
}

/* input a line of basic */
void do_basic(void)
{
    fprintf(stderr,"error: command comming soon.\n");
}

/* input a C style string text string */
void do_fcn(void)
{
    char *p;
    char *s;
    int a;

    p = strtok(NULL,WS);
    if (!p) {
	fprintf(stderr,"error: address expected.\n");
	return;
    }
    a = strtol(p, NULL, 16);
    s = strtok(NULL,"\"\'");
    if (s == NULL) {
	fprintf(stderr,"error: string expected %s\n",s);
	return;
    }
    if (send_write(s, a, strlen(s)+1)){
	fprintf(stderr,"error: command timeout\n.");
	return;
    }
}

/* process user input */
void input(char *line)
{
    uint8_t *ptr;
    add_history(line);
    ptr = strtok(line, WS);
    if (ptr == NULL) return;
    if (*ptr == 0) return;
    if (*ptr == '\n') return;
    if (!strcmp(ptr,"list")) { db_list(); return; }
    else if (!strcmp(ptr,"probe")) { do_probe(); return; }
    else if (!strcmp(ptr,"connect")) { do_connect(); return; }
    else if (!strcmp(ptr,"dump")) { do_dump(); return; }
    else if (!strcmp(ptr,"poke")) { do_poke(); return; }
    else if (!strcmp(ptr,"exec")) { do_exec(); return; }
    else if (!strcmp(ptr,"dasm")) { do_dasm(); return; }
    else if (!strcmp(ptr,"reboot")) { do_reboot(); return; }
    else if (!strcmp(ptr,"load")) { do_load(); return; }
    else if (!strcmp(ptr,"loadf")) { do_loadf(); return; }
    else if (!strcmp(ptr,"fcn")) { do_fcn(); return; }
    else if (!strcmp(ptr,"basic")) { do_basic(); return; }
    else if (!strcmp(ptr,"exit")) exit(1);
    else if (!strcmp(ptr,"quit")) exit(1);
    else
	printf("error: unrecognized command.\n");
}

/* process received packets from network */
void input_net(void)
{
    int ret;
    int x;

    x = sizeof(raddr);
    ret = recvfrom(sd, buf, BUFLEN, 0,
		   (struct sockaddr *)&raddr, &x);
    if (ret < 0){
	perror("recv");
    } else {
	if ((buf[0] & MT_MASK) == MT_ANN)
	    db_add(&raddr);
    }
}

/* check the status of clients */
void process_time(void)
{
    uint8_t c;
    int x;

    for (x = 0; x < DBNUM; x++){
	if (db[x].flag != DF_EMPTY && time(NULL) > db[x].time){
	    db[x].flag -= 1;
	    db[x].time = time(NULL) + PTIME;
	}
    }
}


int main(int argc, char *argv[])
{
    int ret;
    int x;
    fd_set set;
    struct timeval tv;

    for (x=0; x<16; x++){
	db[x].flag = DF_EMPTY;
    }
  
    sd = socket(AF_INET, SOCK_DGRAM, 0);
    if (!sd) {
	perror("socket");
	exit(1);
    }

    laddr.sin_family = AF_INET;
    laddr.sin_port = htons(6999);

    raddr.sin_family = AF_INET;
  
    ret = bind(sd, (struct sockaddr *)&laddr, INETZ);
    if (ret){
	perror("bind");
	exit(1);
    }

    rl_callback_handler_install("> ", input);
    while (1) {
	FD_ZERO(&set);
	FD_SET(0,&set);
	FD_SET(sd,&set);
	tv.tv_sec = 1;
	tv.tv_usec = 0;
	ret = select(sd+1, &set, NULL, NULL, &tv);
	if (ret == 0){
	    process_time();
	    continue;
	}
	if (ret < 0){
	    perror("select");
	    exit(1);
	}
	if (FD_ISSET(sd,&set)) {
	    input_net();
	}
	if (FD_ISSET(0,&set)) {
	    rl_callback_read_char();
	}
    }

    close(sd);
    exit(0);
}



