module ecs;

import world;

/* Represents a unique entity identifier. */
struct Entity @export("Entity")
{
	ulong id;
	uint gen;
}

fn bool Entity.eql(Entity* self, Entity other) @operator(==) @export("entity_equals")
{
	return self.id == other.id && self.gen == other.gen;
}


interface Component
{
}

struct With<TypeA>
{
	TypeA* dummy;
}
struct Without<TypeA>
{
	TypeA* dummy;
}

interface SystemParam
{
}


macro void @system_param_init($Type, #param, World* world)
{
	$if $Type == World*:
		#param = world;
	$else
		$if $Type::kind == TypeKind.POINTER:
			{
				$Type $dummy_ptr = ($Type)1;
				String $type_name = type_to_name($Typeof(*$dummy_ptr));
				$if $type_name.len >= 6 && $type_name[0..5] == "ResMut":
					#param = ($Type)world.get_resource($Typeof(*$dummy_ptr)::inner);
				$else
					$if $defined($Typeof(*$dummy_ptr).init_system_param):
						#param.init_system_param(world);
					$else
						$error "Type " +++ $Type::name +++ " is not a valid SystemParam";
					$endif
				$endif
			}
		$else
			{
				String $type_name = type_to_name($Type);
				$if $type_name.len >= 3 && $type_name[0..2] == "Res":
					#param = *(($Type*)world.get_resource($Type::inner));
				$else
					$if $defined($Type.init_system_param):
						#param.init_system_param(world);
					$else
						$error "Type " +++ $Type::name +++ " is not a valid SystemParam";
					$endif
				$endif
			}
		$endif
	$endif
}
