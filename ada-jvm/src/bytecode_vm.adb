with Ada.Unchecked_Conversion;

package body Bytecode_VM is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_32;

   Stack_Capacity : constant := 256;
   Local_Capacity : constant := 256;

   subtype Stack_Index is Natural range 0 .. Stack_Capacity;
   type Operand_Stack is array (Positive range 1 .. Stack_Capacity)
     of Interfaces.Integer_32;
   subtype Local_Index is Natural range 0 .. Local_Capacity - 1;
   type Local_Variables is array (Local_Index) of Interfaces.Integer_32;
   type Initialization_Flags is array (Local_Index) of Boolean;

   function To_Unsigned is new Ada.Unchecked_Conversion
     (Interfaces.Integer_32, Interfaces.Unsigned_32);
   function To_Signed is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_32, Interfaces.Integer_32);

   function Execute
     (Code : Ada.Streams.Stream_Element_Array)
      return Interfaces.Integer_32
   is
      Stack : Operand_Stack;
      Top   : Stack_Index := 0;
      PC    : Ada.Streams.Stream_Element_Offset := Code'First;
      Locals : Local_Variables := [others => 0];
      Initialized : Initialization_Flags := [others => False];

      procedure Push (Value : Interfaces.Integer_32) is
      begin
         if Top = Stack_Capacity then
            raise Bytecode_Error with "operand stack overflow";
         end if;
         Top := Top + 1;
         Stack (Top) := Value;
      end Push;

      function Pop return Interfaces.Integer_32 is
         Value : Interfaces.Integer_32;
      begin
         if Top = 0 then
            raise Bytecode_Error with "operand stack underflow";
         end if;
         Value := Stack (Top);
         Top := Top - 1;
         return Value;
      end Pop;

      function Read_Byte return Ada.Streams.Stream_Element is
         Value : Ada.Streams.Stream_Element;
      begin
         if PC > Code'Last then
            raise Bytecode_Error with "truncated bytecode operand";
         end if;
         Value := Code (PC);
         PC := PC + 1;
         return Value;
      end Read_Byte;

      function Read_Signed_Byte return Interfaces.Integer_32 is
         Value : constant Ada.Streams.Stream_Element := Read_Byte;
      begin
         if Value < 128 then
            return Interfaces.Integer_32 (Value);
         end if;
         return Interfaces.Integer_32 (Value) - 256;
      end Read_Signed_Byte;

      function Read_Branch_Offset return Interfaces.Integer_32 is
         High : constant Interfaces.Integer_32 :=
           Interfaces.Integer_32 (Read_Byte);
         Low  : constant Interfaces.Integer_32 :=
           Interfaces.Integer_32 (Read_Byte);
         Value : constant Interfaces.Integer_32 := High * 256 + Low;
      begin
         if Value < 32_768 then
            return Value;
         end if;
         return Value - 65_536;
      end Read_Branch_Offset;

      procedure Branch
        (Opcode_PC : Ada.Streams.Stream_Element_Offset;
         Take      : Boolean)
      is
         Target : Interfaces.Integer_32;
      begin
         declare
            Displacement : constant Interfaces.Integer_32 :=
              Read_Branch_Offset;
         begin
            if Take then
               Target := Interfaces.Integer_32 (Opcode_PC) + Displacement;
               if Target < Interfaces.Integer_32 (Code'First)
                 or else Target > Interfaces.Integer_32 (Code'Last)
               then
                  raise Bytecode_Error with "branch target outside method";
               end if;
               PC := Ada.Streams.Stream_Element_Offset (Target);
            end if;
         end;
      end Branch;

      procedure Load_Local (Index : Local_Index) is
      begin
         if not Initialized (Index) then
            raise Bytecode_Error with "read of uninitialized local variable";
         end if;
         Push (Locals (Index));
      end Load_Local;

      procedure Store_Local (Index : Local_Index) is
      begin
         Locals (Index) := Pop;
         Initialized (Index) := True;
      end Store_Local;

      Opcode : Ada.Streams.Stream_Element;
      Left   : Interfaces.Integer_32;
      Right  : Interfaces.Integer_32;
      Opcode_PC : Ada.Streams.Stream_Element_Offset;
   begin
      while PC <= Code'Last loop
         Opcode_PC := PC;
         Opcode := Read_Byte;
         case Opcode is
            when 16#02# .. 16#08# =>
               Push (Interfaces.Integer_32 (Opcode) - 3);
            when 16#15# =>
               Load_Local (Local_Index (Read_Byte));
            when 16#1A# .. 16#1D# =>
               Load_Local (Local_Index (Natural (Opcode - 16#1A#)));
            when 16#10# =>
               Push (Read_Signed_Byte);
            when 16#36# =>
               Store_Local (Local_Index (Read_Byte));
            when 16#3B# .. 16#3E# =>
               Store_Local (Local_Index (Natural (Opcode - 16#3B#)));
            when 16#60# =>
               Right := Pop;
               Left := Pop;
               Push (To_Signed (To_Unsigned (Left) + To_Unsigned (Right)));
            when 16#64# =>
               Right := Pop;
               Left := Pop;
               Push (To_Signed (To_Unsigned (Left) - To_Unsigned (Right)));
            when 16#68# =>
               Right := Pop;
               Left := Pop;
               Push (To_Signed (To_Unsigned (Left) * To_Unsigned (Right)));
            when 16#6C# =>
               Right := Pop;
               Left := Pop;
               if Right = 0 then
                  raise Bytecode_Error with "integer division by zero";
               elsif Left = Interfaces.Integer_32'First
                 and then Right = -1
               then
                  Push (Interfaces.Integer_32'First);
               else
                  Push (Left / Right);
               end if;
            when 16#84# =>
               declare
                  Index : constant Local_Index := Local_Index (Read_Byte);
                  Delta : constant Interfaces.Integer_32 := Read_Signed_Byte;
               begin
                  if not Initialized (Index) then
                     raise Bytecode_Error with
                       "increment of uninitialized local variable";
                  end if;
                  Locals (Index) :=
                    To_Signed (To_Unsigned (Locals (Index))
                               + To_Unsigned (Delta));
               end;
            when 16#99# =>
               Left := Pop;
               Branch (Opcode_PC, Left = 0);
            when 16#9A# =>
               Left := Pop;
               Branch (Opcode_PC, Left /= 0);
            when 16#9F# =>
               Right := Pop;
               Left := Pop;
               Branch (Opcode_PC, Left = Right);
            when 16#A0# =>
               Right := Pop;
               Left := Pop;
               Branch (Opcode_PC, Left /= Right);
            when 16#A1# =>
               Right := Pop;
               Left := Pop;
               Branch (Opcode_PC, Left < Right);
            when 16#A2# =>
               Right := Pop;
               Left := Pop;
               Branch (Opcode_PC, Left >= Right);
            when 16#A3# =>
               Right := Pop;
               Left := Pop;
               Branch (Opcode_PC, Left > Right);
            when 16#A4# =>
               Right := Pop;
               Left := Pop;
               Branch (Opcode_PC, Left <= Right);
            when 16#A7# =>
               Branch (Opcode_PC, True);
            when 16#AC# =>
               if Top = 0 then
                  raise Bytecode_Error with "ireturn requires a stack value";
               end if;
               return Pop;
            when others =>
               raise Bytecode_Error with
                 "unsupported opcode" & Ada.Streams.Stream_Element'Image
                   (Opcode);
         end case;
      end loop;

      raise Bytecode_Error with "method bytecode ended without ireturn";
   end Execute;
end Bytecode_VM;
