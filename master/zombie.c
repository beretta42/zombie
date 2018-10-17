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
#include <errno.h>

#define WS      " \n\t"
#define INETZ   sizeof(struct sockaddr_in)
#define BUFLEN  256
#define LBUFLEN 256


int sd;
struct sockaddr_in laddr;
struct sockaddr_in raddr;
uint8_t buf[BUFLEN];
uint8_t obuf[BUFLEN];
uint8_t lbuf[LBUFLEN];

struct db_entry {
  int flag;
  struct sockaddr_in addr;
  int cap;
};

#define DF_EMPTY 0
#define DF_USED  1

#define MT_ANN   0
#define MT_READ  1
#define MT_WRITE 2
#define MT_EXEC  3
#define MT_MASK  0x0f
#define MF_RESP  0x80

#define DBNUM    16

struct db_entry db[DBNUM];

int conn = -1;


/* Add a client to the database */
void db_add(struct sockaddr_in *addr)
{
  int x;
  /* don't add if already in database */
  for (x = 0; x < DBNUM; x++){
    if (db[x].flag != DF_EMPTY &&
	db[x].addr.sin_addr.s_addr == addr->sin_addr.s_addr) {
      return;
    }
  }
  /* add to first free db entry */
  for (x = 0; x < DBNUM; x++){
    if (db[x].flag == DF_EMPTY){
      db[x].flag = DF_USED;
      memcpy(&db[x].addr, addr, sizeof(struct sockaddr_in));
      db[x].cap = 0;
      return;
    }
  }
}



/* print a list of zombies in the database */
void db_list(void)
{
  int x;
  for (x = 0; x < DBNUM; x++) {
    if (db[x].flag != DF_EMPTY){
      printf("%c[%d] %s\n", x == conn ? '*' : ' ',
	     x, inet_ntoa(db[x].addr.sin_addr) );
    }
  }
  printf("\n");
}


/* prompt the user */
void prompt(void)
{
  printf("> ");
  fflush(stdout);
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

void do_dump(void)
{
  int x;
  uint8_t *ptr;
  uint16_t addr = ntohs(*(uint16_t *)(buf + 3));
  uint16_t len =  ntohs(*(uint16_t *)(buf + 5));
  for(x = 0; x < len; x++){
    if (!(x % 16)){
      printf("\n%.4x  ", addr);
      addr += 16;
    }
    printf("%.2x ", buf[x+7]);
  }    
  printf("\n");
}

/* dump memory from our target client */
void send_dump(void)
{
  int x;
  char *p;
  int ret;
  struct timeval tm;
  int retry = 3;
  
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
  memset(obuf, '\0', BUFLEN);
  p = obuf;
  *p++ = MT_READ;
  *p++ = 0;
  *p++ = 0;
  *p++ = x >> 8;
  *p++ = x & 0xff;
  *p++ = 0;
  *p++ = 0x80;
  while (retry--) {
    sendto(sd,obuf,7,0,
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
    if ((buf[0] & MT_MASK) == MT_READ){
      do_dump();
      return;
    }
  }
}

void send_poke(void)
{
  int a;
  int x;
  int l;
  int len = 0;
  uint8_t *p;
  char *s;

  s = strtok(NULL, WS);
  if (!s){
    fprintf(stderr, "error: address expected\n");
    return;
  }
  a = strtol(s, NULL, 16);
  a &= 0xffff;
  memset(obuf, 0, BUFLEN);
  p = obuf;
  *p++ = MT_WRITE;
  *p++ = 0;
  *p++ = 0;
  *p++ = a >> 8;
  *p++ = a & 0xff;
  p +=2;
  while (1){
    s = strtok(NULL, WS);
    if (!s) break;
    x = strtol(s, NULL, 16);
    *p++ = x & 0xff;
    l++;
  }
  if (!l ) {
    fprintf(stderr, "error: expecting at least one hex byte\n");
    return;
  }	    
  obuf[5] = l >> 8;
  obuf[6] = l & 0xff;
  sendto(sd,obuf, p - obuf, 0,
	 (struct sockaddr *)&db[conn].addr,
	 sizeof(struct sockaddr_in));
}


void send_exec(void)
{
  int a;
  int x;
  int ret;
  uint8_t *p;
  char *s;
  struct timeval tm;
  int retry = 3;

  s = strtok(NULL, WS);
  if (!s){
    fprintf(stderr, "error: address expected\n");
    return;
  }
  a = strtol(s, NULL, 16);
  a &= 0xffff;
  memset(obuf, 0, BUFLEN);
  p = obuf;
  *p++ = MT_EXEC;
  *p++ = 0;
  *p++ = 0;
  *p++ = a >> 8;
  *p++ = a & 0xff;
  *p++ = 0;
  *p++ = 0;
  while (retry--) {
    sendto(sd,obuf, p - obuf, 0,
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
    if ((buf[0] & MT_MASK) == MT_EXEC){
      printf("ok\n");
      return;
    }
  }
  fprintf(stderr, "error: command timeout.\n");
}

/* process user input */
void input(void)
{
  uint8_t *ptr;
  
  ptr = strtok(lbuf, WS);
  if (ptr == NULL) return;
  if (*ptr == 0) return;
  if (*ptr == '\n') return;
  if (!strcmp(ptr,"list")) { db_list(); return; }
  else if (!strcmp(ptr,"connect")) { do_connect(); return; }
  else if (!strcmp(ptr,"dump")) { send_dump(); return; }
  else if (!strcmp(ptr,"poke")) { send_poke(); return; }
  else if (!strcmp(ptr,"exec")) { send_exec(); return; }
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



int main(int argc, char *argv[])
{
  int ret;
  int x;
  fd_set set;

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

  prompt();
  while (1) {
    FD_ZERO(&set);
    FD_SET(0,&set);
    FD_SET(sd,&set);
    ret = select(sd+1, &set, NULL, NULL, NULL);
    if (ret < 0){
      perror("select");
      exit(1);
    }
    if (FD_ISSET(sd,&set)) {
      input_net();
    }
    if (FD_ISSET(0,&set)) {
      ret = read(0,lbuf,LBUFLEN);
      if (ret < 0 ){
	perror("read");
	exit(1);
      }
      lbuf[ret] = 0;
      input();
      prompt();
    }
  }

  close(sd);
  exit(0);
}



