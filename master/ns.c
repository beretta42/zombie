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

#include "zombie.h"

#define INETZ   sizeof(struct sockaddr_in)
#define PTIME   15

int sd;
struct sockaddr_in laddr;
struct sockaddr_in raddr;
uint8_t obuf[BUFLEN];



struct db_entry {
    int flag;
    struct sockaddr_in addr;
    int cap;
    uint8_t name[16];
    time_t time;
};

#define DF_EMPTY 0
#define DF_IFFY  1
#define DF_USED  2

#define DBNUM    256

struct db_entry db[DBNUM];

void db_print(int num)
{
    /* for debugging: print the new entry */
    printf("[%d] %s:%d ", num, inet_ntoa(db[num].addr.sin_addr),
	   ntohs(db[num].addr.sin_port));
    printf("%c ", (db[num].flag == DF_IFFY) ? '?' : ' ');
    printf("%s\n", db[num].name);
}


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
    strncpy(db[x].name, buf + 7, 16);
    db[x].name[15] = 0;
    db_print(x);
}

void in_query(void)
{
    int x;

    b_op |= MT_RESP;
    for (x = 0; x < DBNUM; x++){
	if (db[x].flag != DF_EMPTY){
	    if (!strncmp(db[x].name, b_data,16))
		goto found;
	}
    }
    b_ret = Z_ERRNF;
    sendto(sd, buf, 8, 0,
	   (struct sockaddr *)&raddr, sizeof(raddr));
    return;
  found:
    b_ret = Z_ERROK;
    memcpy(b_data,&(db[x].addr.sin_addr),4);
    memcpy(b_data+4,&(db[x].addr.sin_port),2);
    sendto(sd, buf, 14, 0,
	   (struct sockaddr *)&raddr, sizeof(raddr));
    return;
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
	if ((buf[0] & MT_MASK) == MT_QUERY){
	    in_query();
	}
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
    laddr.sin_port = htons(PORT);

    raddr.sin_family = AF_INET;
  
    ret = bind(sd, (struct sockaddr *)&laddr, INETZ);
    if (ret){
	perror("bind");
	exit(1);
    }

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
	}
    }

    close(sd);
    exit(0);
}



