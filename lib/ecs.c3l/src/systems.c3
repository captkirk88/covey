module ecs;

import world;
import std::core::mem;

macro void @run_system_helper(World* self, $SysType, #system) @private
{
	$if $SysType::params.len > 0:
		{
			$Typefrom($SysType::params[0].type) $first_dummy;
			String $first_name = type_to_name($Typeof($first_dummy));
			$if $first_name.len >= 3 && $first_name[0..2] == "On{":
				{
					bool $has_event = false;
					for (uint i = 0; i < self.message_queue.records_len; i++)
					{
						if (self.message_queue.records[i].type == $first_dummy.type_a())
						{
							$has_event = true;
							break;
						}
					}
					if (!$has_event) return;
				}
			$endif
		}
	$endif

	$for var $idx = 0; $idx < 8; $idx++:
		$if $idx < $SysType::params.len:
			$Typefrom($SysType::params[$idx].type) $dummy;
			$if $idx > 0:
				{
					String $param_name = type_to_name($Typeof($dummy));
					$if $param_name.len >= 3 && $param_name[0..2] == "On{":
						$error "On{...} must be the first parameter of the system";
					$endif
				}
			$endif
			String $idx_str;
			$if $idx == 0:
				$idx_str = "0";
			$else
				$if $idx == 1:
					$idx_str = "1";
				$else
					$if $idx == 2:
						$idx_str = "2";
					$else
						$if $idx == 3:
							$idx_str = "3";
						$else
							$if $idx == 4:
								$idx_str = "4";
							$else
								$if $idx == 5:
									$idx_str = "5";
								$else
									$if $idx == 6:
										$idx_str = "6";
									$else
										$idx_str = "7";
									$endif
								$endif
							$endif
						$endif
					$endif
				$endif
			$endif
			$expand("$Typeof($dummy) p_" +++ $idx_str +++ ";");
			$expand("@system_param_init($Typeof($dummy), p_" +++ $idx_str +++ ", self);");
		$endif
	$endfor

	$if $SysType::params.len == 0:
		#system();
	$else
		$if $SysType::params.len == 1:
			#system(p_0);
		$else
			$if $SysType::params.len == 2:
				#system(p_0, p_1);
			$else
				$if $SysType::params.len == 3:
					#system(p_0, p_1, p_2);
				$else
					$if $SysType::params.len == 4:
						#system(p_0, p_1, p_2, p_3);
					$else
						$if $SysType::params.len == 5:
							#system(p_0, p_1, p_2, p_3, p_4);
						$else
							$if $SysType::params.len == 6:
								#system(p_0, p_1, p_2, p_3, p_4, p_5);
							$else
								$if $SysType::params.len == 7:
									#system(p_0, p_1, p_2, p_3, p_4, p_5, p_6);
								$else
									$if $SysType::params.len == 8:
										#system(p_0, p_1, p_2, p_3, p_4, p_5, p_6, p_7);
									$else
										$error "systems with more than 8 parameters are not supported";
									$endif
								$endif
							$endif
						$endif
					$endif
				$endif
			$endif
		$endif
	$endif
}

macro void @run_system(World* self, #system) @private
{
	@run_system_helper(self, $Typeof(#system), #system);
}

macro void World.run_systems(World* self, ...) 
{
	$for var $i = 0; $i < $vaarg.len; $i++:
		{
			bool $is_exclusive = false;
			$for var $p_idx = 0; $p_idx < $Typeof($vaarg[$i])::params.len; $p_idx++:
				$if $Typeof($vaarg[$i])::params[$p_idx].type == World*::typeid:
					$is_exclusive = true;
				$endif
			$endfor

			$if $is_exclusive:
				self.flush_commands();
				@run_system(self, $vaarg[$i]);
			$else
				@run_system(self, $vaarg[$i]);
			$endif
		}
	$endfor

	self.flush_commands();
	self.clear_messages();
}
