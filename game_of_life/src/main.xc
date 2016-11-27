// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 512                  //image height
#define  IMWD 512                  //image width
#define  num_workers 4
#define  num_rounds 100
#define  file_in "512x512.pgm"
#define  file_out "testout512.pgm"

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


uchar GetCell(uchar byte, uchar index) {
    uchar cell;
    cell = (((byte << (index)) >> (7)) & 1);
    return cell;
}

void Worker(uchar id, chanend worker_distributor) {
    uchar board_segment[((IMWD/2)/8)+ 2 ][(IMHT/(num_workers/2))+ 2];
    uchar a;
    uchar count = 0;
    uchar processing = 1;
    uchar packedline = 0;
    uchar byteindex = 0;
    uchar cellindex = 0;

    while (processing){
    for(int i = 0; i < (IMHT/(num_workers/2)+2); i++) {
        for(int j = 0; j < ((IMWD/16)+2); j++) {
            worker_distributor :> board_segment[j][i];
        }
    }


    //PROCESSING
    worker_distributor <: (uchar)id;
    for(int y = 1; y < (IMHT/(num_workers/2)+1); y ++) {
        byteindex = 0;
        for(int x = 1; x < ((IMWD/16)+1); x ++) { //for all the cells in the board check the number of adjacent cells
            packedline = 0;
            for( uchar z = 0; z < 8; z++ ) {
                count = 0;

                for (int k=-1; k<2; k++) {
                    for (int l=-1; l<2; l++) {
                        if(k || l) {
                            if((z + l) > 7) {
                                byteindex = x+1;
                                cellindex = 0;
                            }
                            else if((z + l) < 0) {
                                byteindex = x-1;
                                cellindex = 7;
                            }
                            else {
                                byteindex = x;
                                cellindex = z + l;
                            }
                            if(GetCell(board_segment[byteindex][y+k], cellindex)) {
                                count++;
                            }
                        }

                    }
                }

                a = count;

                //calculate whether the cell should die
                 if(GetCell(board_segment[x][y], z) == 1) {

                         if( a < 2 || a > 3) {
                             packedline |= (0 << 7-z);
                         }
                         else {
                             packedline |= (1 << 7-z);
                         }
                 }
                 else {
                     if(a == 3) {
                         packedline |= (1 << 7-z);
                     }
                     else {
                         packedline |= (0 << 7-z);
                     }
                 }

            } // z loop
            worker_distributor <: packedline;
         } // x loop
     } // y loop
    worker_distributor :> processing;
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
  uchar packedx = 0;
  uchar offsetx = 0;

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }
  to_leds <: 4;
  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    offsetx = 0;
    _readinline( line, IMWD );
    for( int x = 0; x < (IMWD/8); x++ ) {
        packedline = 0;
        for( uchar z = 0; z < 8; z++ ) {
            packedx = offsetx+z;
            if (line[packedx] == 255) {
                packedline |= (1 << 7-z);
            }
            else if (line[packedx] == 0){
                packedline |= (0 << 7-z);
            }
        }
        offsetx = offsetx + 8;
        c_out <: packedline;
    }
  }


  //Close PGM image file
  _closeinpgm();
  free(line);
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
  int offset_x;
  int offset_y;

  timer t;
  long start_time = 0;
  long end_time = 0;
  float time_taken = 0;


  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

  printf("Waiting for Button Press...\n");
  fromButtons :> button_input;

  if (button_input == 14) {
      //INITIALISATION
      for( int y = 0; y < IMHT; y++ ) {   //go through all lines
          for( int x = 0; x < (IMWD/8); x++ ) { //go through each pixel per line

              c_in :> current_board[x][y]; //read in and store pixel value
          }
      }
      data_in_complete = 1;
  }
 // printf("start_time: %d\n", start_time);

  printf( "Processing...\n" );

  while((processing_rounds < max_rounds) && data_in_complete) {
      t :> start_time;
//      printf("processing round %d begun..\n", processing_rounds+1);
      select {
          case c_out :> please_output: {
              please_output = 1;
//              printf("Output requested...\n");
              to_leds <: 2;

              for( int j = 0; j < IMHT; j++ ) {
                for( int i = 0; i < (IMWD/8); i++ ) {
                   c_out <: (uchar)current_board[i][j];
                }
              }

              break;
          }
          case fromAcc :> paused: {
              if (paused) {
                  to_leds <: 8;
                  printf("\n-------------------------------\n");
                  printf("Processing rounds completed: %d\n", processing_rounds+1);
                  printf("-------------------------------\n\n");
                  while (paused) {
                      fromAcc :> paused;
                  }
              }
              break;
          }
          default: {
              please_output = 0;
              break;
          }
      }

       workers_finished = 0;
       offset_x = 0;
       offset_y = 0;

       if(processing_rounds % 2) { //alternating led flashing
           to_leds <: 1;
       }
       else {
           to_leds <: 5;
       }


       par for(int i = 0; i < num_workers; i++) { //sending data to the workers
           switch(i) {
              case 0:
                   offset_x = 0;
                   offset_y = 0;
                   break;

              case 1:
                   offset_x = (IMWD/16);
                   offset_y = 0;
                   break;

              case 2:
                   offset_x = 0;
                   offset_y = (IMHT/(num_workers/2));
                   break;

              case 3:
                   offset_x = (IMWD/16);
                   offset_y = (IMHT/(num_workers/2));
                   break;
          }

              for(int j = -1; j < ((IMHT/(num_workers/2))+1); j ++) {
                  for(int k = -1; k < ((IMWD/16)+1); k++) {
                      distributor_worker[i] <: (uchar) current_board[xadd(offset_x, k)][yadd(offset_y, j)];
                  }
              }
        }

        while(workers_finished<num_workers) { //recieving data from the workers
           par select {
               case distributor_worker[uchar j] :> uchar data:

                 switch(j) {
                   case 0:
                        offset_x = 0;
                        offset_y = 0;
                        break;

                   case 1:
                        offset_x = (IMWD/16);
                        offset_y = 0;
                        break;

                   case 2:
                        offset_x = 0;
                        offset_y = (IMHT/(num_workers/2));
                        break;

                   case 3:
                        offset_x = (IMWD/16);
                        offset_y = (IMHT/(num_workers/2));
                        break;
               }

               for(int l = 0; l < (IMHT/(num_workers/2)); l ++) {
                   for(int k = 0; k < (IMWD/16); k++) {
                       distributor_worker[j] :> current_board[xadd(offset_x, k)][yadd(offset_y, l)];
                   }
               }

               workers_finished++;

               break;
           }
        }

//        printf( "%d processing round completed...\n", (processing_rounds+1));
        processing_rounds++;
        if (processing_rounds < max_rounds) {
            for (uchar z = 0; z < num_workers; z++) {
                distributor_worker[z] <: (uchar) 1;
            }
        }
        t :> end_time;
        end_time -= start_time;
        time_taken = (end_time*10) % (2^31);
//        printf("end time: %d nanoseconds\n", end_time*10);
        printf("%f\n", time_taken);
  }

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
    uchar packedx = 0;
    uchar offsetx = 0;
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
                    line[packedx] = 255;
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

    //send signal to distributor after first tilt
      if (x>100) {
        toDist <: (uchar) 1;
        tilted = (uchar) 1;
      }
      if (x<100 && tilted == 1) {
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
            printf("SW1...\n");
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
        case from_data_in :> pattern:
           // printf("pattern: %d\n", pattern);
            p <: pattern;                //send pattern to LED port
            break;

        case from_distributor :> pattern:
            //printf("pattern: %d\n", pattern);
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

chan c_inIO, c_outIO, c_control, distributor_worker[num_workers], buttons_to_dist, buttons_to_dataout, leds_data_in, leds_distributor;    //extend your channel definitions here

par {
    on tile[0] : i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0] : orientation(i2c[0],c_control);        //client thread reading orientation data
    on tile[0] : DataInStream(file_in, c_inIO, leds_data_in);          //thread to read in a PGM image
    on tile[1] : DataOutStream(file_out, c_outIO, buttons_to_dataout);       //thread to write out a PGM image
    on tile[0] : distributor(c_inIO, c_outIO, c_control, buttons_to_dist, distributor_worker, leds_distributor);//thread to coordinate work on image
    on tile[1] : Worker((uchar)1, distributor_worker[0]);
    on tile[1] : Worker((uchar)2, distributor_worker[1]);
    on tile[1] : Worker((uchar)3, distributor_worker[2]);
    on tile[1] : Worker((uchar)4, distributor_worker[3]);
    on tile[0] : button_listener(buttons, buttons_to_dist, buttons_to_dataout);
    on tile[0] : showLEDs(leds, leds_data_in, leds_distributor);
  }

  return 0;
}
