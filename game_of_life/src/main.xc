// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 256                  //image height
#define  IMWD 256                 //image width

typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

uchar current_board[IMWD][IMHT];
uchar next_board[IMWD][IMHT];

int next_board_segment[4][(IMWD/2)][(IMHT/2)];

void print_next_board() {
    //print the next_board_segments
          for(int k = 0; k < 4; k ++) {
              for( int j = 0; j < (IMHT/2); j++ ) {
                    printf("\n");
                    for( int i = 0; i < (IMWD/2); i++ ) {
                        printf( "-%4.1d ", next_board_segment[k][i][j]);
                    }
               }
              printf("\n");
          }
}

void initialise_segments() {
    for(int i = 0; i < 4; i++) {
        for(int j = 0; j < (IMWD/2); j ++) {
            for(int k= 0; k < (IMHT/2); k ++) {
                next_board_segment[i][j][k] = 0; //initialises board values to 0
            }
        }
    }
}

int xadd (int i, int a) {
    i += a;
    while (i < 0) i += IMWD;
    while (i >= IMWD) i -= IMWD;
    return i;
}

int yadd (int i, int a) {
    i += a;
    while (i < 0) i += IMHT;
    while (i >= IMHT) i -= IMHT;
    return i;
}

int adjacent_to ( int x, int y) {
    int k, l, count;

    count = 0;

    /* go around the cell */

    for (k=-1; k<=1; k++) {
        for (l=-1; l<=1; l++) {

            if (k || l) {
                if (current_board[xadd(x,k)][yadd(y,l)] == 255) {
                    count++;
                }
            }
        }
    }
    return count;
}

int GameRules(int x, int y) {
    int a;

    a = adjacent_to(x, y);

    if(current_board[x][y] == 255) {
        if( a < 2 || a > 3) {
            return 0;
        }
        else {
            return 255;
        }
    }
    else {
        if( a == 3) {
            return 255;
        }
        else {
            return 0;
        }
    }
}
void Master(chanend master_to_worker[4]) {
    int worker_id = 0;
    int workersfinished = 0;
    while(workersfinished < 4) {
        select {
                case master_to_worker[int i] :> worker_id:
                printf("Worker %d completed segment\n", worker_id);
                workersfinished++;
                break;
            }
    }
}

void Worker(int id, int next_board_segment[(IMWD/2)][(IMHT/2)], chanend worker_to_master) {
    printf("Worker %d started\n", id);
    int segment_processed = id;
    int offset_x;
    int offset_y;

    if((id-1) == 0) {
            offset_x = 0;
            offset_y = 0;
        }
        else if((id-1) == 1) {
            offset_x = (IMWD/2);
            offset_y = 0;
        }
        else if((id-1) == 2) {
            offset_x = 0;
            offset_y = (IMHT/2);
        }
        else if((id-1) == 3) {
            offset_x = (IMWD/2);
            offset_y = (IMHT/2);
        }

    for(int i = 0; i < (IMHT/2); i++) {
        for(int j = 0; j < (IMWD/2); j++) {
            next_board_segment[j][i] = GameRules(offset_x + j, offset_y + i);
        }
    }
    worker_to_master <: segment_processed;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      //printf( "-%4.1d ", line[ x ] ); //show image values
    }
    //printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc)
{
  uchar val;
  chan master_worker[4];
  int processing_rounds;
  int max_rounds;


  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  processing_rounds = 0;
  max_rounds = 4;

  printf( "Processing...\n" );



  //INITIALISATION
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      current_board[x][y] = val;
    }
  }

  initialise_segments();

  while(processing_rounds < max_rounds) {
      //setting next_board values to current_board
        int offset_x = 0;
        int offset_y = 0;

        for(int i = 0; i < 4; i ++) {
            if(i == 0) {
                offset_x = 0;
                offset_y = 0;
            }
            else if(i == 1) {
                offset_x = (IMWD/2);
                offset_y = 0;
            }
            else if(i == 2) {
                offset_x = 0;
                offset_y = (IMHT/2);
            }
            else if(i == 3) {
                offset_x = (IMWD/2);
                offset_y = (IMHT/2);
            }

              for(int j = 0; j < (IMHT/2); j ++) {
                  for(int k = 0; k < (IMWD/2); k++) {
                      next_board_segment[i][k][j] = current_board[offset_x + k][offset_y + j];
                  }
              }
        }

        par{
            Master(master_worker);
            Worker(1, next_board_segment[0], master_worker[0]);
            Worker(2, next_board_segment[1], master_worker[1]);
            Worker(3, next_board_segment[2], master_worker[2]);
            Worker(4, next_board_segment[3], master_worker[3]);
        }


        //set the current board equal to the next_board_segments
        offset_x = 0;
        offset_y = 0;

        for(int i = 0; i < 4; i ++) {
            if(i == 0) {
                offset_x = 0;
                offset_y = 0;
            }
            else if(i == 1) {
                offset_x = (IMWD/2);
                offset_y = 0;
            }
            else if(i == 2) {
                offset_x = 0;
                offset_y = (IMHT/2);
            }
            else if(i == 3) {
                offset_x = (IMWD/2);
                offset_y = (IMHT/2);
            }

              for(int j = 0; j < (IMHT/2); j ++) {
                  for(int k = 0; k < (IMWD/2); k++) {
                      current_board[offset_x + k][offset_y + j] = next_board_segment[i][k][j];
                  }
              }
        }


        printf( "\n%d processing round completed...\n", (processing_rounds+1));
        processing_rounds ++;
  }
  //Prints out the board
  for( int j = 0; j < IMHT; j++ ) {
      //printf("\n");
          for( int i = 0; i < IMWD; i++ ) {
              //printf( "-%4.1d ", current_board[i][j]);
                 c_out <: (uchar)current_board[i][j];
             }
  }


}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
    //printf( "DataOutStream: Line written...\n" );
  }
  printf("data out should be done\n");
  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

char infname[] = "256x256.pgm";     //put your input image path here
char outfname[] = "testout256.pgm"; //put your output image path here
chan c_inIO, c_outIO, c_control;    //extend your channel definitions here

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);        //client thread reading orientation data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control);//thread to coordinate work on image
  }

  return 0;
}
