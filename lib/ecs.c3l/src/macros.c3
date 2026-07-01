module ecs;

macro typeid type_to_typeid($Type)
{
	return $Type::typeid;
}

macro cast_ptr($Type, void* ptr)
{
	return ($Type*)ptr;
}

macro get_filter_type($Type)
{
	return $Typeof(*(($Type*)null).dummy);
}

macro type_to_name($Type)
{
	return $Type::name;
}
