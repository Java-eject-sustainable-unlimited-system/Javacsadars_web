with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with Class_File_Reader;
with Ada.Text_IO;
with Bytecode_VM;
with Interfaces;

procedure Ada_Jvm is
   use Ada.Command_Line;
   use Ada.Streams;
   use Ada.Text_IO;
   use type Ada.Streams.Stream_IO.Count;
   use type Interfaces.Integer_32;

   Max_Code_Length : constant Stream_Element_Offset := 65_536;
   subtype Code_Buffer is Stream_Element_Array (1 .. Max_Code_Length);
   Max_Class_File_Length : constant Stream_IO.Count := 16 * 1024 * 1024;

   type Stream_Element_Array_Access is access Stream_Element_Array;
   procedure Release is new Ada.Unchecked_Deallocation
     (Stream_Element_Array, Stream_Element_Array_Access);

   procedure Check
     (Code     : Stream_Element_Array;
      Expected : Interfaces.Integer_32)
   is
      Actual : constant Interfaces.Integer_32 := Bytecode_VM.Execute (Code);
   begin
      if Actual /= Expected then
         raise Program_Error with
           "self-test failed: expected"
           & Interfaces.Integer_32'Image (Expected)
           & ", received" & Interfaces.Integer_32'Image (Actual);
      end if;
   end Check;

   procedure Run_Self_Tests is
      Class_Bytes : constant Stream_Element_Array :=
        [16#CA#, 16#FE#, 16#BA#, 16#BE#, 0, 0, 0, 52, 0, 10,
         1, 0, 1, Character'Pos ('T'),
         7, 0, 1,
         1, 0, 16, Character'Pos ('j'), Character'Pos ('a'),
         Character'Pos ('v'), Character'Pos ('a'), Character'Pos ('/'),
         Character'Pos ('l'), Character'Pos ('a'), Character'Pos ('n'),
         Character'Pos ('g'), Character'Pos ('/'), Character'Pos ('O'),
         Character'Pos ('b'), Character'Pos ('j'), Character'Pos ('e'),
         Character'Pos ('c'), Character'Pos ('t'),
         7, 0, 3,
         1, 0, 5, Character'Pos ('v'), Character'Pos ('a'),
         Character'Pos ('l'), Character'Pos ('u'), Character'Pos ('e'),
         1, 0, 3, Character'Pos ('('), Character'Pos (')'),
         Character'Pos ('I'),
         1, 0, 4, Character'Pos ('C'), Character'Pos ('o'),
         Character'Pos ('d'), Character'Pos ('e'),
         1, 0, 10, Character'Pos ('S'), Character'Pos ('o'),
         Character'Pos ('u'), Character'Pos ('r'), Character'Pos ('c'),
         Character'Pos ('e'), Character'Pos ('F'), Character'Pos ('i'),
         Character'Pos ('l'), Character'Pos ('e'),
         1, 0, 6, Character'Pos ('T'), Character'Pos ('.'),
         Character'Pos ('j'), Character'Pos ('a'), Character'Pos ('v'),
         Character'Pos ('a'),
         16#00#, 16#21#, 0, 2, 0, 4, 0, 0, 0, 0, 0, 1,
         0, 9, 0, 5, 0, 6, 0, 1,
         0, 7, 0, 0, 0, 15, 0, 1, 0, 0, 0, 0, 0, 3, 16#10#, 42, 16#AC#,
         0, 0, 0, 0,
         0, 1, 0, 8, 0, 0, 0, 2, 0, 9];
      Extracted_Code : Class_File_Reader.Method_Code_Buffer;
      Extracted_Length : Natural;
   begin
      Check ([16#10#, 8, 16#10#, 5, 16#60#, 16#AC#], 13);
      Check ([16#02#, 16#10#, 3, 16#6C#, 16#AC#], 0);
      Check ([16#10#, 16#FD#, 16#AC#], -3);
      Check ([16#10#, 7, 16#10#, 6, 16#68#, 16#AC#], 42);
      Check ([16#10#, 9, 16#10#, 4, 16#64#, 16#AC#], 5);
      Check ([16#10#, 7, 16#3B#, 16#1A#, 16#10#, 5, 16#60#, 16#AC#], 12);
      Check
        ([16#03#, 16#99#, 0, 6, 16#10#, 1, 16#AC#, 16#10#, 42, 16#AC#], 42);
      Check
        ([16#04#, 16#99#, 0, 6, 16#10#, 1, 16#AC#, 16#10#, 42, 16#AC#], 1);
      Check
        ([16#03#, 16#3B#, 16#1A#, 16#10#, 3, 16#A2#, 0, 9,
          16#84#, 0, 1, 16#A7#, 16#FF#, 16#F7#, 16#1A#, 16#AC#], 3);
      Class_File_Reader.Extract_Static_Method
        (Class_Bytes  => Class_Bytes,
         Method_Name  => "value",
         Descriptor   => "()I",
         Code         => Extracted_Code,
         Code_Length  => Extracted_Length);
      Check (Extracted_Code (1 .. Stream_Element_Offset (Extracted_Length)), 42);
      Put_Line ("Ada JVM bytecode self-tests passed.");
   end Run_Self_Tests;

   procedure Run_File (Path : String) is
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : Code_Buffer;
      Last   : Stream_Element_Offset;
   begin
      Ada.Streams.Stream_IO.Open
        (File, Ada.Streams.Stream_IO.In_File, Path);
      if Ada.Streams.Stream_IO.Size (File) >
        Ada.Streams.Stream_IO.Count (Max_Code_Length)
      then
         raise Bytecode_VM.Bytecode_Error with
           "bytecode input exceeds 64 KiB";
      end if;
      Ada.Streams.Stream_IO.Read (File, Buffer, Last);
      Ada.Streams.Stream_IO.Close (File);

      if Last = 0 then
         raise Bytecode_VM.Bytecode_Error with "empty bytecode input";
      end if;
      Put_Line
        (Interfaces.Integer_32'Image
           (Bytecode_VM.Execute (Buffer (1 .. Last))));
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Run_File;

   procedure Run_Class_File
     (Path       : String;
      Method     : String;
      Descriptor : String)
   is
      File        : Ada.Streams.Stream_IO.File_Type;
      Size        : Stream_IO.Count;
      Buffer      : Stream_Element_Array_Access := null;
      Last        : Stream_Element_Offset;
      Code        : Class_File_Reader.Method_Code_Buffer;
      Code_Length : Natural;
   begin
      Stream_IO.Open (File, Stream_IO.In_File, Path);
      Size := Stream_IO.Size (File);
      if Size = 0 or else Size > Max_Class_File_Length then
         raise Class_File_Reader.Class_File_Error with
           "class-file input must be between 1 byte and 16 MiB";
      end if;
      Buffer :=
        new Stream_Element_Array
          (1 .. Stream_Element_Offset (Size));
      Stream_IO.Read (File, Buffer.all, Last);
      Stream_IO.Close (File);

      Class_File_Reader.Extract_Static_Method
        (Class_Bytes => Buffer (1 .. Last),
         Method_Name => Method,
         Descriptor  => Descriptor,
         Code        => Code,
         Code_Length => Code_Length);
      Release (Buffer);
      Put_Line
        (Interfaces.Integer_32'Image
           (Bytecode_VM.Execute
              (Code (1 .. Stream_Element_Offset (Code_Length)))));
   exception
      when others =>
         if Stream_IO.Is_Open (File) then
            Stream_IO.Close (File);
         end if;
         if Buffer /= null then
            Release (Buffer);
         end if;
         raise;
   end Run_Class_File;
begin
   if Argument_Count = 1 and then Argument (1) = "--self-test" then
      Run_Self_Tests;
   elsif Argument_Count = 1 then
      Run_File (Argument (1));
   elsif Argument_Count = 4 and then Argument (1) = "--class-file" then
      Run_Class_File (Argument (2), Argument (3), Argument (4));
   else
      Put_Line
        (Standard_Error,
         "Usage: ada_jvm --self-test"
         & " | ada_jvm <raw-method-code-file>"
         & " | ada_jvm --class-file <file.class> <method> <descriptor>");
      Set_Exit_Status (Failure);
   end if;
exception
   when Error : Bytecode_VM.Bytecode_Error =>
   Put_Line
     (Standard_Error,
      "Bytecode error: " & Ada.Exceptions.Exception_Message (Error));
   Set_Exit_Status (Failure);
   when Error : Class_File_Reader.Class_File_Error =>
     Put_Line
       (Standard_Error,
        "Class-file error: " & Ada.Exceptions.Exception_Message (Error));
     Set_Exit_Status (Failure);
   when Error : others =>
   Put_Line
     (Standard_Error,
      Ada.Exceptions.Exception_Information (Error));
      Set_Exit_Status (Failure);
end Ada_Jvm;
