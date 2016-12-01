// COMS20001 - Cellular Automaton Farm
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <stdlib.h>
#include "pgmIO.h"
#include "i2c.h"

#define  readimage 0               //whether the image should be read in or processed on board
#define  IMHT 256                 //image height
#define  IMWD 256                 //image width
#define  num_workers 4             //either 2 or 4
#define  num_rounds 100             //process iterations
#define  file_in "64_alive.pgm"           //the image to be processed
#define  file_out "testout256gen.pgm"       //the image file to output the result to

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0] : port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0] : port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //port for buttons
on tile[0] : out port leds = XS1_PORT_4F; //port for leds

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


///////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Takes in 2 values and calculates their sum mod IMWD/8. Used when wrapping round the x axis of the board.
//
///////////////////////////////////////////////////////////////////////////////////////////////////////////
int xadd (int i, int a) {
    i = i + a;
    while (i < 0) {
        i = i + (IMWD/8);
    }
    while (i >= (IMWD)/8) {
        i = i - (IMWD/8);
    }
    return i;
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Takes in 2 values and calculates their sum mod IMHT. Used when wrapping round the y axis of the board.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////
int yadd (int i, int a) {
    i = i + a;
    while (i < 0) {
        i = i + IMHT;
    }
    while (i >= IMHT) {
        i = i - IMHT;
    }
    return i;
}

////////////////////////////////////////////////////////////////////////////////////////////
//
// Takes in a value to 'mod' and the size of long (2^32)-1. Used when calculating the time.
//
///////////////////////////////////////////////////////////////////////////////////////////
unsigned long timer_mod(unsigned long x, unsigned long max_ticks) {
    if ((x % max_ticks) > -1) {
        return (unsigned long) (x % max_ticks);
    } else {
        return (unsigned long) ((x + max_ticks) % max_ticks);
    }
}

////////////////////////////////////////////////////////////////////
//
// Returns the difference between the start and end time in seconds.
//
////////////////////////////////////////////////////////////////////
float calc_time(unsigned long start_time, unsigned long end_time) {
    float start_time_seconds = (float) start_time/100000000;
    float end_time_seconds = (float) end_time/100000000;
    return (float) (end_time_seconds - start_time_seconds);
}

//////////////////////////////////////////////////////////////////////////
//
// Takes a byte and an index and returns the bit at the index in the byte.
//
//////////////////////////////////////////////////////////////////////////
uchar GetCell(uchar byte, uchar index) {
    uchar cell;
    cell = (((byte << (index)) >> (7)) & 1); //The target bit is attained by shifting the byte left so that the index is the most significant bit then shifted right 7 so that the byte is either 1 or 0.
    return cell;
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Recieves a segment of the image from the distributor, applies the GoL rules then sends it back to the distributor.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void Worker(uchar id, chanend worker_distributor) {
    uchar board_segment[((IMWD/(num_workers/2))/8)+ 2 ][(IMHT/(num_workers/2))+ 2]; //stores the image segment
    uchar count = 0; //the number of adjacent live cells for each cell
    uchar processing = 1;
    uchar packedline = 0;
    uchar byteindex = 0;
    uchar cellindex = 0;

    while (processing){ //Recieve the image from the distributor
        for(int i = 0; i < (IMHT/(num_workers/2)+2); i++) { //the leftmost, rightmost top and bottom cells are the border cells
            for(int j = 0; j < ((IMWD/16)+2); j++) {
                worker_distributor :> board_segment[j][i];
            }
        }

        for(int y = 1; y < (IMHT/(num_workers/2)+1); y ++) { //apply the GoL rules to all of the cells in the segment (excluding the border cells).
            byteindex = 0;
            for(int x = 1; x < ((IMWD/16)+1); x ++) {
                packedline = 0;
                for( uchar z = 0; z < 8; z++ ) {
                    count = 0;

                    for (int k=-1; k<2; k++) { //works out the number of surrounding cells
                        for (int l=-1; l<2; l++) {
                            if(k || l) {
                                if((z + l) > 7) { //if accessing a cell to the right of the current byte
                                    byteindex = x+1;
                                    cellindex = 0;
                                }
                                else if((z + l) < 0) { //if accessing a cell to the left of the current byte
                                    byteindex = x-1;
                                    cellindex = 7;
                                }
                                else { //if the index of the neighbour is at the same x position as the target cell
                                    byteindex = x;
                                    cellindex = z + l;
                                }
                                if(GetCell(board_segment[byteindex][y+k], cellindex)) { //if the neighbour is alive increment count
                                    count++;
                                }
                            }

                        }
                    }

                    uchar a = count; //for brevity in the GoL logic

                    //calculates whether the cell should die
                     if(GetCell(board_segment[x][y], z) == 1) { //if the cell is alive

                             if( a < 2 || a > 3) {
                                 packedline |= (0 << 7-z); //place a 0 at the zth index in the byte
                             }
                             else {
                                 packedline |= (1 << 7-z); //place a 1 at the zth index in the byte
                             }
                     }
                     else { //if the cell is dead
                         if(a == 3) {
                             packedline |= (1 << 7-z);
                         }
                         else {
                             packedline |= (0 << 7-z);
                         }
                     }

                } // z loop
                worker_distributor <: (uchar)id; //send the workers id to the distributor, telling the distributor that the worker has processed a line.
                worker_distributor <: (int)(x-1); //sends the workers x coordinate -1 since we've offset the x value by 1.
                worker_distributor <: (int)(y-1); //sends the workers x coordinate -1 since we've offset the y value by 1.
                worker_distributor <: packedline; //sends the line of 8 cells).
             } // x loop
         } // y loop
        worker_distributor :> processing; //Waits until the distributor says it can continue with the next round of processing.
    }
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out, chanend to_leds)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );
  uchar packedline = 0;
  int packedx = 0;
  int offsetx = 0;

  if(readimage) {
      //Open PGM file
        res = _openinpgm( infname, IMWD, IMHT );
        if( res ) {
          printf( "DataInStream: Error openening %s\n.", infname );
          return;
        }
        //Read image line-by-line and compress 8 bytes to one byte. Send resulting bytes to channel c_out
        for( int y = 0; y < IMHT; y++ ) {
          offsetx = 0;
          _readinline( line, IMWD );
          for( int x = 0; x < (IMWD/8); x++ ) {
              packedline = 0;
              for( uchar z = 0; z < 8; z++ ) {
                  packedx = offsetx+z;
                  if (line[packedx] == 255) { //if it is white
                      packedline |= (1 << 7-z);
                  }
                  else if (line[packedx] == 0){ //if it is black
                      packedline |= (0 << 7-z);
                  }
              }
              offsetx = offsetx + 8;
              c_out <: packedline;
          }
        }
        //Close PGM image file
        _closeinpgm();
  }
  else { //If generating an image on board
      for(int i = 0; i < IMHT*(IMWD/8); i++ ) {
          uchar random = rand() % 256; //calculate a random 8 bit byte
          c_out <: random; //send it to the distributor
      }
  }
  printf( "DataInStream: Done...\n" );
  return;
}

////////////////////////////////////////////////////////////////////////////////
//
// Controls when IO should occur and distributes/collects data from the workers.
//
////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromButtons, chanend distributor_worker[num_workers], chanend to_leds)
{
  int processing_rounds = 0;
  int max_rounds = num_rounds;
  uchar current_board[(IMWD/8)][IMHT];
  uchar workers_finished;
  uchar data_in_complete = 0;
  uchar button_input;
  uchar please_output;
  uchar paused = 0;
  uchar livecellcount = 0;
  int offsets[(num_workers*2)];

  timer t; //variables used for timing
  unsigned long start_time = 0;
  unsigned long pause_start = 0;
  unsigned long pause_end = 0;
  unsigned long end_time = 0;
  float total_time_taken = 0;
  float pause_time = 0;
  float total_time_paused = 0;
  unsigned long max_ticks = 4294967295; //the maximum value of unsigned long before overflow

  offsets[0] = 0; //Calculates the offsets for the board divisions
  offsets[1] = 0;
  offsets[2] = (IMWD/16);
  offsets[3] = 0;
  offsets[4] = 0;
  offsets[5] = (IMHT/(num_workers/2));
  offsets[6] = (IMWD/16);
  offsets[7] = (IMHT/(num_workers/2));

  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf("Waiting for Button Press...\n");
  fromButtons :> button_input;

  if (button_input == 14) { //If SW1 pressed
      to_leds <: 4;
      for( int y = 0; y < IMHT; y++ ) {   //go through all lines
          for( int x = 0; x < (IMWD/8); x++ ) { //go through each byte per line
              c_in :> current_board[x][y]; //read in and store byte value
          }
      }
      data_in_complete = 1;
      printf( "Processing...\n" );
  }

  while((processing_rounds < max_rounds) && data_in_complete) {
      t :> start_time;
      select {
          case c_out :> please_output: { //Receiving output request from data out stream
              please_output = 1;
              to_leds <: 2;

              for( int j = 0; j < IMHT; j++ ) {
                for( int i = 0; i < (IMWD/8); i++ ) {
                   c_out <: (uchar)current_board[i][j]; //send every byte to the data out stream
                }
              }

              break;
          }
          case fromAcc :> paused: { //Receivning pause request from the accelerometer
              if (paused) {
                  t :> pause_start;
                  livecellcount = 0;
                  to_leds <: 8;
                  printf("\n-------------------------------\n");
                  printf("Processing rounds completed: %d\n", processing_rounds+1);

                  for( int y = 0; y < IMHT; y++ ) {
                      for( int x = 0; x < IMWD/8; x++ ) {
                          for( uchar z = 0; z < 8; z++ ) {
                              if (GetCell(current_board[x][y], z) == 1) {
                                  livecellcount++; //if the cell is alive increment the count
                              }
                          }
                      }
                  }

                  printf("Number of alive cells: %d\n", livecellcount);
                  printf("Time elapsed: %f seconds (excluding paused time)\n", total_time_taken);
                  printf("-------------------------------\n\n");
                  while (paused) {
                      fromAcc :> paused;
                  }
                  t :> pause_end;
              }
              break;
          }
          default: {
              please_output = 0;
              break;
          }
      }

      if(processing_rounds % 2) { //alternating led flashing
        to_leds <: 4;
      }
      else {
        to_leds <: 5;
      }

       workers_finished = 0;

       par (int i = 0; i < num_workers; i++) { //sending data to the workers
            for(int j = -1; j < ((IMHT/(num_workers/2))+1); j ++) {
                for(int k = -1; k < ((IMWD/16)+1); k++) {
                    distributor_worker[i] <: (uchar) current_board[xadd(offsets[2*i], k)][yadd(offsets[(2*i)+1], j)];
                }
             }
       }

        int processed_cells = 0;
        while(processed_cells<(IMHT*(IMWD/8))) { //recieving data from the workers
           select {
               case distributor_worker[uchar j] :> uchar data: //worker j has finished processing a byte
               int k;
               int l;
               distributor_worker[j] :> k; //x coordinate
               distributor_worker[j] :> l; //y coordinate
               distributor_worker[j] :> current_board[xadd(offsets[2*j], k)][yadd(offsets[(2*j)+1], l)]; //store byte

               processed_cells++;

               break;
           }
        }

        processing_rounds++;
        if (processing_rounds < max_rounds) {
            for (uchar z = 0; z < num_workers; z++) {
                distributor_worker[z] <: (uchar) 1; //tell the workers they can start processing a new round.
            }
        }
        t :> end_time;

        float iteration_time = calc_time(timer_mod(start_time, max_ticks), timer_mod(end_time, max_ticks)); //calculate timing
        pause_time = calc_time(timer_mod(pause_start, max_ticks), timer_mod(pause_end, max_ticks));
        pause_start = 0;
        pause_end = 0;
        if (iteration_time < 0) {
            iteration_time += 42.94967295;
        }
        if (pause_time > 0) {
            iteration_time = iteration_time - pause_time;
        }
        total_time_taken += iteration_time;
        total_time_paused += pause_time;
        printf("%f\n", iteration_time);
        pause_time = 0;
  }

  printf("total time elapsed: %f seconds\n", total_time_taken);
  printf("Processing complete...\n");
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in, chanend from_buttons)
{
  while(1) {
    uchar SW2_button_in;
    uchar packedline = 0;
    int packedx = 0;
    int offsetx = 0;
    from_buttons :> SW2_button_in;

    c_in <: (uchar) 1;
    printf("DataOut request sent...\n");
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
          offsetx = 0;
        for( int x = 0; x < IMWD/8; x++ ) {
            c_in :> packedline;
            for( uchar z = 0; z < 8; z++ ) {
                packedx = offsetx + z;
                if (GetCell(packedline, z) == 1) {
                    line[packedx] = 255; //unpacking the bytes
                }
                else if (GetCell(packedline, z) == 0){
                    line[packedx] = 0;
                }
            }
            offsetx += 8;
        }
        _writeoutline( line, IMWD );
    }
    //Close the PGM image
    _closeoutpgm();
    printf( "DataOutStream: Done...\n" );

  }
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
  uchar tilted = 0;

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

    //send signal to distributor after tilt
      if (x>20) {
        toDist <: (uchar) 1;
        tilted = (uchar) 1;
      }
      if (x<20 && tilted == 1) {
          toDist <: (uchar) 0;
          tilted = (uchar) 0;
      }
  }
}

void button_listener(in port b, chanend to_dist, chanend to_dataout) {
    uchar input;
    while (1) {
        b when pinseq(15) :> input; //no buttons pressed
        b when pinsneq(15) :> input; //some button pressed
        if (input == 14) {
            to_dist <: input;

            if(readimage) {
                printf("Reading image...\n");
            }
            else {
                printf("Generating image... \n");
            }

        } else if (input == 13) {
            to_dataout <: input;
        }
    }
}

int showLEDs(out port p, chanend from_data_in, chanend from_distributor) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (1) {
    select {
        case from_data_in :> pattern:    //Receives the pattern from data in when it starts
            p <: pattern;                //send pattern to LED port
            break;

        case from_distributor :> pattern: //Receives the pattern from the distributor
            p <: pattern;
            break;
    }

  }
  return 0;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

chan c_inIO, c_outIO, c_control, c_distributor_worker[num_workers], c_buttons_to_dist, c_buttons_to_dataout, c_leds_data_in, c_leds_distributor;    //extend your channel definitions here

par {
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0] : orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[1] : DataInStream(file_in, c_inIO, c_leds_data_in);          //thread to read in a PGM image
    on tile[0] : DataOutStream(file_out, c_outIO, c_buttons_to_dataout);       //thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, c_buttons_to_dist, c_distributor_worker, c_leds_distributor);//thread to coordinate work on image
    par (uchar i = 0; i < num_workers; i++ ){
        on tile[1] : Worker((uchar)(i+1), c_distributor_worker[i]); //threads to process the image
    }
    on tile[0] : button_listener(buttons, c_buttons_to_dist, c_buttons_to_dataout);
    on tile[0] : showLEDs(leds, c_leds_data_in, c_leds_distributor);
  }

  return 0;
}
