module tracer_tb;
  int 	 fd; 			// Variable for file descriptor handle
  int 	 value;

  initial begin
    // 1. Lets first open a new file and write some contents into it
    fd = $fopen ("trial", "w");
    for (int i = 0; i < 5; i++)
      $fdisplay (fd, "Iteration = %0d", i);
    $fclose(fd);

    // 2. Let us now read back the data we wrote in the previous step
    fd = $fopen ("trial", "r");

    // fscanf returns the number of matches
    while ($fscanf (fd, "0x%h", value) == 1) begin
      $display ("Line: %h", value);
    end

    // Close this file handle
    $fclose(fd);
  end
endmodule